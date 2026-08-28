# Fix 2 — Floating windows fall behind tiling windows

Branch: `2_Fix_Floating_Windows`
File touched: `dwm.c` (plus one one-word correction in `config/window-rules.toml`)

**Nothing in this document has been applied.** Every section gives the exact
current text and the exact replacement text.

---

## 1. What is actually happening

`restack()` (`dwm.c:2597`) is stock dwm, and stock dwm only guarantees that the
**selected** floating window is on top. Here is the current body:

```c
	if (m->sel->isfloating || !m->lt[m->sellt]->arrange)
		XRaiseWindow(dpy, m->sel->win);
	if (m->lt[m->sellt]->arrange) {
		wc.stack_mode = Below;
		wc.sibling = m->barwin;
		for (c = m->stack; c; c = c->snext)
			if (!c->isfloating && ISVISIBLE(c)) {
				XConfigureWindow(dpy, c->win, CWSibling|CWStackMode, &wc);
				wc.sibling = c->win;
			}
	}
```

The second block walks the visible **tiled** clients and chains each one
directly *below the bar window*. Because the Quickshell panel (`m->barwin`) sits
at the very top of the X stack, "directly below the bar" means "at the top of
everything else". The tiled windows are therefore lifted into a contiguous block
just under the panel — **above** any floating window that is not the currently
selected one.

Reproduction, and it matches the report exactly:

1. Open a window that a rule forces to float (`isfloating=1`) in a tiling layout.
2. Click a tiled window, or press the focus-stack key to move to one.
3. `focus()` → `restack(selmon)` runs. The tiled block is re-chained under the
   panel. The float is now underneath it.

`focus()` (`dwm.c:3185`) never raises anything, so nothing puts the float back.

### Why `alwaysontop` windows look fine and plain floats do not

`restack()` ends with `restackprioritywindows()` (`dwm.c:2653`), which calls
`raisealwaysontopclients()`. That re-raises every client with `alwaysontop` or
`ewmhabove` set, so the Quickshell launcher, settings window, etc. survive.

There is no equivalent pass for a plain floating client. That single missing
pass is the bug.

### Secondary defect: `wc.sibling = m->barwin` when there is no bar

`m->barwin` is `0` (`None`) on a monitor that has not adopted a panel yet — a
fresh monitor from `createmon()` (`dwm.c:1099`), a monitor whose panel just went
away (`dwm.c:1031`, `dwm.c:2943`), or the window between dwm start-up and
Quickshell mapping its dock.

`XConfigureWindow` with `CWSibling` and a sibling of `None` raises `BadWindow`,
and `xerror()` (`dwm.c:5403`) swallows **all** `BadWindow` unconditionally:

```c
	if (ee->error_code == BadWindow
```

So the request is silently dropped and the tiled windows are never restacked at
all on that monitor. It fails quietly today; it must not fail quietly once the
stacking order actually matters.

### Third defect (config, not code): the `RAIL` rule never floats

`config/window-rules.toml` line 29:

```toml
  { class="RAIL",           float=1 },
```

The TOML loader reads the key `isfloating` (`dwm.c:3799`); there is no `float`
key. This rule silently does nothing. See §5.

---

## 2. The stacking order we want

Top to bottom:

| # | Layer | Raised by |
|---|-------|-----------|
| 1 | Visible fullscreen clients | `raisefullscreenclients()` |
| 2 | Override-redirect popups/menus with `raise` | `overridewindows` loop |
| 3 | Panel + tray (`barwin`, `traywin`) | `restackprioritywindows()` |
| 4 | `alwaysontop` / `_NET_WM_STATE_ABOVE` clients | `raisealwaysontopclients()` |
| 5 | **Plain floating clients** ← *currently missing* | `raisefloatingclients()` (new) |
| 6 | Tiled clients, in focus order | `restack()` |

Layers 1–4 already exist and keep their current relative order. The fix inserts
layer 5 underneath them and makes layer 6 land reliably at the bottom.

The new pass goes **inside `restackprioritywindows()`**, not inside `restack()`.
That is deliberate: `restackprioritywindows()` is also called from `mapnotify()`
(`dwm.c:1988`), `propertynotify()` (`dwm.c:2335`), `setfullscreen()`
(`dwm.c:2365`), and from `restack()`'s early `!m->sel` return path. Putting the
float pass there fixes every one of those paths at once instead of just the
`restack()` one.

---

## 3. Changes to `dwm.c`

### 3.1 Forward declaration

**Find** (`dwm.c:244`–`dwm.c:246`):

```c
static void raisefullscreenclients(Client *c);
static void raisealwaysontopclients(Client *c);
static void restackprioritywindows(void);
```

**Replace with:**

```c
static void raisefullscreenclients(Client *c);
static void raisealwaysontopclients(Client *c);
static void raisefloatingclients(Client *c);
static void restackprioritywindows(void);
```

---

### 3.2 New `raisefloatingclients()`

**Find** (`dwm.c:2678`–`dwm.c:2686`, the existing `raisealwaysontopclients`):

```c
void
raisealwaysontopclients(Client *c)
{
	if (!c)
		return;
	raisealwaysontopclients(c->snext);
	if ((c->alwaysontop || c->ewmhabove) && ISVISIBLE(c))
		XRaiseWindow(dpy, c->win);
}
```

**Replace with:**

```c
void
raisealwaysontopclients(Client *c)
{
	if (!c)
		return;
	raisealwaysontopclients(c->snext);
	if ((c->alwaysontop || c->ewmhabove) && ISVISIBLE(c))
		XRaiseWindow(dpy, c->win);
}

/* A floating client is only guaranteed to be on top while it is selected:
 * restack() chains the tiled clients directly beneath the bar, which is the
 * top of the stack, so every unselected float ends up buried under them. This
 * lifts the plain floats back out as one layer, below the always-on-top,
 * panel, override and fullscreen layers that restackprioritywindows() raises
 * afterwards.
 *
 * The recursion walks m->stack to its tail and raises on the way back out, so
 * clients come up least-recently-focused first and the focus order inside the
 * floating layer is preserved. Clients belonging to a higher layer are skipped
 * here rather than raised twice.
 */
void
raisefloatingclients(Client *c)
{
	if (!c)
		return;
	raisefloatingclients(c->snext);
	if (c->isfloating && ISVISIBLE(c)
	    && !c->alwaysontop && !c->ewmhabove && !isvisiblefullscreen(c))
		XRaiseWindow(dpy, c->win);
}
```

> `isvisiblefullscreen()` is declared at `dwm.c:242` and defined at `dwm.c:2626`,
> so it is in scope here.

---

### 3.3 Run the new pass from `restackprioritywindows()`

**Find** (`dwm.c:2652`–`dwm.c:2662`):

```c
void
restackprioritywindows(void)
{
	int revert;
	Monitor *m;
	OverrideWindow *ow;
	Window focused;

	for (m = mons; m; m = m->next)
		raisealwaysontopclients(m->stack);
```

**Replace with:**

```c
void
restackprioritywindows(void)
{
	int revert;
	Monitor *m;
	OverrideWindow *ow;
	Window focused;

	/* Order matters: each pass raises to the very top, so the last pass to
	 * touch a window wins. Plain floats first, then always-on-top, then the
	 * panel, then override popups, then fullscreen. */
	for (m = mons; m; m = m->next)
		raisefloatingclients(m->stack);
	for (m = mons; m; m = m->next)
		raisealwaysontopclients(m->stack);
```

The rest of the function is unchanged.

---

### 3.4 Make the tiled chain survive a missing bar window

**Find** (`dwm.c:2597`–`dwm.c:2621`, the whole of `restack`):

```c
void
restack(Monitor *m)
{
	Client *c;
	XEvent ev;
	XWindowChanges wc;

	// drawbar(m);
	if (!m->sel) {
		restackprioritywindows();
		return;
	}
	if (m->sel->isfloating || !m->lt[m->sellt]->arrange)
		XRaiseWindow(dpy, m->sel->win);
	if (m->lt[m->sellt]->arrange) {
		wc.stack_mode = Below;
		wc.sibling = m->barwin;
		for (c = m->stack; c; c = c->snext)
			if (!c->isfloating && ISVISIBLE(c)) {
				XConfigureWindow(dpy, c->win, CWSibling|CWStackMode, &wc);
				wc.sibling = c->win;
			}
	}
	restackprioritywindows();
	XSync(dpy, False);
	while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
}
```

**Replace with:**

```c
void
restack(Monitor *m)
{
	Client *c;
	XEvent ev;
	Window sibling;
	XWindowChanges wc;

	// drawbar(m);
	if (!m->sel) {
		restackprioritywindows();
		return;
	}
	if (m->sel->isfloating || !m->lt[m->sellt]->arrange)
		XRaiseWindow(dpy, m->sel->win);
	if (m->lt[m->sellt]->arrange) {
		/* Chain the tiled clients downwards in focus order. The first one
		 * anchors to the bar when the monitor has adopted a panel; a monitor
		 * that has not (a fresh monitor from createmon(), or one whose panel
		 * just unmapped) has barwin == None, and CWSibling with a None
		 * sibling is a BadWindow that xerror() discards silently -- which
		 * used to leave the whole monitor unstacked. Lowering the first
		 * client instead puts the tiled block at the bottom, which is where
		 * restackprioritywindows() is about to assume it is anyway. */
		sibling = m->barwin;
		wc.stack_mode = Below;
		for (c = m->stack; c; c = c->snext)
			if (!c->isfloating && ISVISIBLE(c)) {
				if (sibling == None) {
					XLowerWindow(dpy, c->win);
				} else {
					wc.sibling = sibling;
					XConfigureWindow(dpy, c->win, CWSibling|CWStackMode, &wc);
				}
				sibling = c->win;
			}
	}
	restackprioritywindows();
	XSync(dpy, False);
	while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
}
```

Behaviour is byte-identical to today whenever `m->barwin` is set, which is the
normal case. The only change is that the no-panel case now produces a correct
stack instead of a silently discarded request.

---

## 4. Why the explicit `XRaiseWindow(dpy, m->sel->win)` stays

It is redundant for the tiling layouts once §3.3 lands — `raisefloatingclients()`
raises `m->stack` head last, and `focus()` moves the focused client to the head
via `detachstack()`/`attachstack()` (`dwm.c:3199`), so the selected float ends up
topmost either way.

It is **not** redundant in the floating layout (`m->lt[m->sellt]->arrange ==
NULL`, the `><>` entry in `config.def.h`). There every client behaves as floating
but most still have `c->isfloating == 0`, so `raisefloatingclients()` skips them
and this line is the only thing raising the selection. Leave it.

---

## 5. `config/window-rules.toml` — the dead `RAIL` rule

Unrelated to the stacking order, but it is the one rule in the file that claims
to float a window and does not.

**Find** (line 29):

```toml
  { class="RAIL",           float=1 },
```

**Replace with:**

```toml
  { class="RAIL",           isfloating=1 },
```

The loader only reads `isfloating` (`dwm.c:3799`); an unknown key is ignored
without a warning. If `RAIL` is also meant to stay above tiled windows, use
`{ class="RAIL", isfloating=1, alwaysontop=1 }` — `applyrules()` (`dwm.c:543`)
implies `isfloating` from `alwaysontop`, but writing both is clearer.

---

## 6. Cost and risk

**Extra X traffic.** `restackprioritywindows()` runs on every `mapnotify`, and
`raisefloatingclients()` adds one `XRaiseWindow` per visible float per call.
`raisealwaysontopclients()` already does exactly this and has been fine, so the
shape of the cost is not new. If a compositing flicker shows up under a heavy
float count, the fix is to cache the last applied order and skip the pass when it
has not changed — do that only if it is actually observed, not pre-emptively.

**Multi-monitor.** The new pass iterates all monitors, matching
`raisealwaysontopclients()`. Floats on one monitor being above tiles on another
is harmless because the regions do not overlap.

**Fullscreen.** Floats are skipped while `isvisiblefullscreen()` is true, and
`raisefullscreenclients()` still runs last, so a fullscreen client is never
covered by a float on the same monitor.

**Drag-to-move.** `movemouse()`/`resizemouse()` call `restack(selmon)`
(`dwm.c:2059`, `dwm.c:2201`) on entry with the dragged client selected, so a
dragged float is raised before the drag and stays raised.

---

## 7. How to verify

Build and run first:

```
make clean && make
```

Then, on a live session:

1. **Core case.** Tiling layout, two tiled terminals, then a window a rule
   floats. Click each tiled window in turn. The float must stay visible over
   both. *(This fails today.)*
2. **Focus-stack case.** Same setup, cycle with the focus-stack key instead of
   the mouse. Same expectation — this path goes through `dwm.c:1410`.
3. **Two floats.** Open two floating windows, click one, then the other. The
   most recently focused one must be on top of the other, and both above all
   tiles.
4. **Layer order.** With a float open, open the Quickshell launcher
   (`alwaysontop=1`). The launcher must cover the float. Close it; the float
   must still cover the tiles.
5. **Panel.** The panel must remain above plain floats and below fullscreen, as
   it is today.
6. **Fullscreen.** Fullscreen a tiled window while a float is open. The float
   must not punch through.
7. **No-panel path (§3.4).** `pkill quickshell`, then cycle focus among tiled
   windows. They must still restack correctly. Restart the shell afterwards.
8. **`togglefloating`.** Toggle a tiled window to floating with a second tiled
   window focused afterwards. The new float must stay on top.

Repo checks that touch this area:

```
make check-dwm-roundtrips
make check-monitor-tags
make check-xvfb-runtime
```

None of them assert stacking order today. If this fix is to be regression-tested,
`tests/test-dwm-x-roundtrips.sh` is the right host — assert with
`xwininfo -root -children` that a floating client's window id precedes every
tiled client's id in the child list after a focus change on the Xvfb display.

---

## 8. Verification status of this proposal

Run against a scratch copy outside the repo — the repository itself is
untouched:

- **§3.1–§3.4 compile clean.** All four edits applied to a copy of `dwm.c`, then
  `gcc -std=c99 -pedantic -Wall` with the project's real pkg-config flags: zero
  errors, zero warnings. Baseline compiled the same way first, for comparison.

Not tested — stacking order can only be confirmed on a running X session. The
root cause in §1 is read directly from the code and the current stacking
contract, but the fix itself has not been observed working. Run the §7 checklist
before claiming it does.
