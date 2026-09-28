# S12-06 -- untrusted text renders as plain text

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-06-untrusted-text-renders-as-plain-text`.
Issue `#169`.

## Change

- **`textFormat: Text.PlainText` everywhere.** Every QML `Text` block in
  `config/quickshell/` now sets it: 91 elements in 23 files, including
  `core/UiText.qml` (so the 158 `UiText` and 7 `IconText` uses inherit it) and
  `core/SectionLabel.qml`. The five Settings views and the inline `PlainText`
  components that already set it are unchanged.
- **Why every element, not a chosen few.** Choosing only the elements that show outside
  text (as the plan listed) would have to be re-decided for every new element. Nothing
  in the shell uses markup (no `text:` with tags, no `RichText`/`StyledText`), so plain
  text everywhere changes nothing visible and makes the rule checkable.
- **How the edit was made.** A script inserted the line into each block that lacked
  it: after `id:` where there is one, matching each file's tabs or spaces, and inline
  for the five one-line blocks.
- `NotificationServer` already advertises `bodyMarkupSupported: false`, which is now
  true of the whole shell.
- `AGENTS.md`: a Quickshell rule that shell text is plain text, and the test that
  enforces it.

## Results (2026-09-27, CachyOS, working tree, nothing committed)

- **`tests/test-quickshell-plain-text-xvfb.sh`** (new, `make check-quickshell-plain-text-xvfb`):
  - Runs real dwm and the full managed shell on an isolated Xvfb and D-Bus session,
    with a local HTTP listener.
  - Sends a notification whose summary and body carry `<img src>` tags aimed at the
    listener, and opens a feh window whose title carries one.
  - **Before the change it fails**, with the listener logging `/body.png` and
    `/summary.png` fetched by the shell.
  - **After the change it passes**: no request arrives, and Qt logs no
    `StyledText ... img tag` warning.
  - Positive controls: the notification is in the shell's history, and the listener
    logs a request that `curl` makes.
- **`tests/test-quickshell-plain-text.sh`** (new, `make check-quickshell-plain-text`):
  PASS.
  - It reads every tracked QML file, counts braces to find each `Text` block, and
    fails on any block without `Text.PlainText`, or on any file that asks for
    `RichText`, `StyledText`, `AutoText` or `MarkdownText`.
  - Against the old tree it reports the missing elements.
- **Mutation checks**, each caught by both tests:
  - removing `PlainText` from the notification summary (the xvfb test sees
    `/summary.png` fetched);
  - removing it from the body (`/body.png`);
  - removing it from `UiText` (Qt parses the panel's window title as `StyledText`).
- **The rest of the suite:**
  - The 31 other static Quickshell and Settings checks from `make check`,
    `check-quickshell-overview-xvfb` and `check-quickshell-large-surfaces-xvfb`: PASS.
  - The Qt QML unit suite: 148 passed, 0 failed.
  - `check-quickshell-qml`: the same warnings as `main`, apart from line numbers.

## Not verified

- Every surface by eye. Plain text changes nothing visible unless a string contained
  markup, which none of the shell's own strings do.
- Tray item tooltips and MPRIS metadata: they go through the same `Text` elements, so
  they are covered by the static rule, but the xvfb test does not send one.
