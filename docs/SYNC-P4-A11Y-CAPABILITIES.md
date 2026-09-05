# Sync Phase 4 — accessibility capability records

Upstream: [`#190`](https://github.com/ChrisTitusTech/dwm-titus/pull/190)
`feat(settings): define accessibility capabilities` (`63e49ab`, +595 / -79).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Pure backend contract, no UI. Foundation for Phases 5, 6, 7 and 8 — all four render
"available / partial / restricted / unavailable" from records this phase defines.

## Context

`scripts/dwm-settings-provider` is the single place Settings asks "can this machine
do X, and if not, why not". It already emits capability records for display, input,
appearance and defaults through `emit_capability()` (`scripts/dwm-settings-provider:99`).

Accessibility has none. `TASKS.md:88` is the open checkbox:

> - [ ] Define capability records for text scaling, contrast, reduced motion, …

Defining the records before any machinery exists means Settings can show an honest
"unavailable — install the managed provider" the moment a pane is added, instead of
a control that silently does nothing.

## Files

| File | Upstream | Note |
| --- | --- | --- |
| `scripts/dwm-settings-provider` | +210 | The bulk |
| `scripts/dwm-settings-input` | +7 | Advertise the accessibility group |
| `tests/test-settings.sh` | +226 | Rewrite onto `tests/lib.sh` |
| `tests/test-settings-input.sh` | +10 | Rewrite onto `tests/lib.sh` |
| `docs/SETTINGS-CAPABILITIES.md` | +4 | Record the new capability ids |

**Not ported:** `docs/P5-ACCESSIBILITY-CAPABILITIES.md` and `docs/P5-STATUS.md` as
upstream wrote them — those are Fedora 44 evidence records. Lyona writes its own
under `docs/evidence/`.

## Changes

### `scripts/dwm-settings-provider` — bound every probe

Upstream tightens the existing probe runner first. Port this: an unbounded
`timeout 2` leaves a wedged helper behind if it ignores `SIGTERM`, and the provider
is called on every Settings open.

```diff
 run_bounded_probe() {
 	shift
 	command_path=$(provider_path "$command_name") || return 1
 	timeout_path=$(command -v timeout 2>/dev/null) || return 1
-	"$timeout_path" 2 "$command_path" "$@" >/dev/null 2>&1
+	"$timeout_path" --signal=TERM --kill-after=1 2 \
+		"$command_path" "$@" >/dev/null 2>&1
 }
```

Apply the same `--signal=TERM --kill-after=1` treatment to every other `timeout`
invocation the file gains below.

### `scripts/dwm-settings-provider` — validate the input snapshot

New `input_snapshot_valid()`. It parses `dwm-settings-input discover` with a single
`awk` pass and rejects a duplicated protocol header, a malformed `device`, `setting`
or `unsupported` row, or a missing header — before any capability is derived from it.

```sh
input_snapshot_valid() {
	command_path=$(provider_path dwm-settings-input) || return 1
	timeout_path=$(command -v timeout 2>/dev/null) || return 1
	input_snapshot=$("$timeout_path" --signal=TERM --kill-after=1 2 \
		"$command_path" discover 2>/dev/null) || return 1
	printf '%s\n' "$input_snapshot" |
		awk -F '\t' '
			NR == 1 && $0 == "input-protocol\t1" {
				header = 1
				protocols++
				next
			}
			$1 == "input-protocol" { protocols++; invalid = 1; next }
			$1 == "device" && NF == 5 && $2 != "" && $3 != "" && $4 != "" && $5 != "" { next }
			$1 == "device" { invalid = 1; next }
			$1 == "setting" && NF == 9 && $2 != "" && $3 != "" && $4 != "" && $5 != "" { next }
			$1 == "setting" { invalid = 1; next }
			$1 == "unsupported" && NF == 4 && $2 != "" && $3 != "" && $4 != "" { next }
			$1 == "unsupported" { invalid = 1; next }
			{ next }
			END { exit(header && protocols == 1 && !invalid ? 0 : 1) }
		'
}
```

One `awk` process for the whole snapshot rather than a shell `while read` loop —
this runs on every Settings open, and the snapshot can carry dozens of device rows.

### `scripts/dwm-settings-provider` — the four capability emitters

Add `emit_text_scale_capability`, `emit_contrast_capability`,
`emit_reduced_motion_capability` and `emit_keyboard_accessibility_capability`,
each following the existing `emit_capability` signature:

```
emit_capability SECTION ID LABEL STATE SCOPE PROVIDER DETAIL
```

**Lyona adaptation.** Upstream's text-scale emitter shells out to
`dwm-settings-personalization`:

```sh
	command_path=$(provider_path dwm-settings-personalization 2>/dev/null || true)
	if [ -z "$command_path" ]; then
		emit_capability appearance accessibility-text-scale 'Text scaling' unavailable user-session \
			dwm-settings-personalization 'Install the managed personalization provider'
		return
	fi
```

In Lyona that helper is `dwm-settings-toolkit` (see the global rules), so every
`dwm-settings-personalization` reference — the probe path, the `PROVIDER` column,
and the operator-facing `DETAIL` string — becomes `dwm-settings-toolkit`:

```sh
	command_path=$(provider_path dwm-settings-toolkit 2>/dev/null || true)
	if [ -z "$command_path" ]; then
		emit_capability appearance accessibility-text-scale 'Text scaling' unavailable user-session \
			dwm-settings-toolkit 'Install the managed personalization provider'
		return
	fi
```

Contrast and reduced motion probe `dwm-accessibility-settings`, which does not exist
until [Phase 5](SYNC-P5-CONTRAST-MOTION.md) — so on this commit they legitimately
report `unavailable`, and Phase 5's tests assert they flip to `available`. That
ordering is deliberate: it proves the capability plumbing is real and not
hard-coded.

Keyboard accessibility gates on `xkbset` plus a live `DISPLAY`, and reports
`restricted` (not `unavailable`) when `xkbset` is present but no X display is
reachable — a headless test run must not look like a broken install.

The upstream emitters validate every field of the helper's status output
(`valid_field` bounding length to 4095, `valid_state` restricting to the four
states) before trusting it. **Port that validation unchanged** — it is the boundary
between an unprivileged helper and the Settings UI, and it is the part most easily
weakened by paraphrasing.

### `scripts/dwm-settings-input` — advertise the group

Seven lines: emit the `accessibility` capability group in `discover` so the provider
above has something to validate. Lyona's `need_setxkbmap()` at
`scripts/dwm-settings-input:43` is the existing seam.

## Deviations from upstream

| Upstream | Lyona | Why |
| --- | --- | --- |
| `dwm-settings-personalization` | `dwm-settings-toolkit` | Pre-fork rename; global rule |
| `dwm-xsettings` probe in the text-scale emitter | Drop | Lyona folds xsettingsd into `dwm-settings-display`'s `write_xsettings_dpi()`, which already degrades silently when `xsettingsd` is absent |
| Bare-`grep` test assertions | `tests/lib.sh` `fail` / `assert_*` | Global rule |

## Verification

```bash
scripts/run-tests make check-shell
scripts/run-tests make check-format
scripts/run-tests make check-settings
```

Manual: run `scripts/dwm-settings-provider capabilities` on a machine **without**
`xkbset` installed and confirm the keyboard-accessibility record reads `unavailable`
with an actionable detail string; install `xkbset` and confirm it flips. Open
Settings → Appearance and confirm the four new capability cards render (no controls
yet — that is Phase 6).

## Closes

`TASKS.md:88` — *Define capability records for text scaling, contrast, reduced
motion, …*
