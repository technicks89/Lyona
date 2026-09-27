# S9-04 -- overview idle cost and many-window performance

Plan: `docs/SYNC-SPRINT-9-OVERVIEW-POLISH.md#s9-04`. Issue `#350`.

`tests/test-overview-load-xvfb.py` (`make check-overview-load-xvfb`) runs the real dwm and Quickshell in Xvfb with the
real `OverviewModel` and `WindowOverview` over a stub `dwmState` holding N windows across 9 tags. Knobs:
`DWM_OVERVIEW_WINDOWS` (60), `DWM_OVERVIEW_CPU_SECONDS` (10), and `..._OPEN_BUDGET`, `..._FILTER_BUDGET`,
`..._NAVIGATE_BUDGET`, `..._CPU_BUDGET`. Absolute CPU and timing budgets are enforced only with
`DWM_OVERVIEW_STRICT=1` on a controlled host. Default runs report all measurements and still require closed CPU
within `DWM_OVERVIEW_CPU_BUDGET` percentage points of the baseline.

## Results (2026-09-27, CachyOS, Xvfb, key events sent one `xdotool` process at a time)

| Windows | Closed CPU before / after 5 open-close cycles | Open | Filter "number 5" | Down x (N-1) | Quickshell RSS |
| --- | --- | --- | --- | --- | --- |
| 60 | 0.0 % / 0.0 % | 52 ms | 108 ms | 0.885 s | 191 MiB |
| 300 | not recorded | not recorded | not recorded | 4.4 s | 190 MiB |
| 600 | not recorded | 70 ms | 131 ms | 8.97 s | 232 MiB |

- The navigation time is dominated by starting one `xdotool` per key press, about 15 ms each; it is not the popup's cost.
- Open and filter times barely move between 60 and 600 windows, and RSS grows about 77 KiB per resident card,
  unmeasurable at any realistic count. **The card list does not need virtualization**; a `Loader` per card would
  matter only in the hundreds of windows.
- The plan asks for 30 s idle windows; the test uses 10 s by default so it stays quick in `make check`. Set
  `DWM_OVERVIEW_CPU_SECONDS=30` for the plan's length.
- The test found a real bug: `Home` left the list scrolled by 18 px with the first tag heading out of view. Fixed by
  `revealCard(card, above)`.
- S9-01 did not land, so the third bullet of the plan (idle cost with cached thumbnails) does not apply.
- Not verified: a real session with real windows, or a slower machine. Budgets are generous on purpose (open 3 s,
  filter 2 s, navigate 8 s for 60 windows, closed CPU within 0.5 points of the start and at most 1 %).
