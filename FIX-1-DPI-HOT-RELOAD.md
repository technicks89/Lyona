# Fix 1 — Make DPI changes take effect without a logout

Branch: `1_Fix_DPI_Hot_Reload`

Files touched:

| File | Why |
|---|---|
| `scripts/dwm-settings-display` | broadcast the DPI change on every live channel, not just the resource database |
| `dwm.c` | rescale borders and gaps when the resource database changes |
| `config/quickshell/core/Theme.qml` | scale the shell's own metrics off the active DPI |
| `config/quickshell/shell.qml` | watch the runtime DPI record and feed it to `Theme` |
| `scripts/autostart.sh` | start the XSETTINGS manager before the saved DPI is applied |
| `scripts/dwm-packages.sh`, `archiso/packages.x86_64` | add `xsettingsd` (and the missing `xorg-xrdb`) |

**Nothing in this document has been applied.** Every section gives the exact
current text and the exact replacement text.

---

## 1. Why a logout is required today

`dwm-settings-display dpi-set N` (`scripts/dwm-settings-display:234`) does exactly
two things:

```bash
	mv -fT "$temporary" "$dpi_resources"     # persist Xft.dpi to dpi.Xresources
	merge_dpi "$value"                       # xrdb -merge Xft.dpi: N
```

`xrdb -merge` rewrites the `RESOURCE_MANAGER` property on the root window. That
is a **startup-time** input for an Xft client: a toolkit reads it when it opens
its first font and caches the result. Nothing already on screen re-reads it.
`TASKS.md:67` already records this — *"live rescaling of running applications
would need an XSETTINGS daemon."*

So today:

| Consumer | Picks up a DPI change |
|---|---|
| Apps launched *after* the change | Yes, via `Xft.dpi` |
| Apps already running | No |
| dwm (borders, snap distance, fontset) | No — dwm never reads `Xft.dpi` at all |
| Quickshell panel and popups | No — `Theme.qml` metrics are hard-coded pixels |
| X server's reported screen DPI | No — `xrandr --dpi` is never called |

The net effect is that only a new session looks right, which is the reported
symptom.

`dpi-apply-saved` (`scripts/dwm-settings-display:265`), the startup-only action
`scripts/autostart.sh:400` calls, has the same limitation — it just calls
`merge_dpi`.

### One thing to fix while we are here

`xrdb` is used by this helper but `xorg-xrdb` is **not** in the dependency map
(`scripts/dwm-packages.sh:15` lists `xorg-server xorg-xinit xorg-xrandr xorg-xset
xorg-xsetroot xorg-xinput xorg-setxkbmap`). `x11_resources_available()`
(`scripts/dwm-settings-display:152`) guards on `command -v xrdb`, so on a system
without it, DPI persistence silently does nothing at all. See §7.

---

## 2. Design

Four independent channels, each best-effort, each failing only itself:

```
  Settings pane  →  dwm-settings-display dpi-set N
                          │
      ┌───────────────────┼───────────────────┬──────────────────┐
      ▼                   ▼                   ▼                  ▼
 RESOURCE_MANAGER     XSETTINGS          xrandr --dpi     runtime state file
 (xrdb -merge)        (xsettingsd)                        dpi.current
      │                   │                   │                  │
      ▼                   ▼                   ▼                  ▼
  dwm PropertyNotify  running GTK/Qt    apps that measure   Quickshell FileView
  → updatedpi()       apps rescale      the screen (Electron,  → Theme.uiScale
  → borders, gaps,    in place          some JVM toolkits)   → panel + popups
    fontset                                                     rescale
      +
  new Xft clients
```

Two properties worth stating up front:

- **The pipeline is additive.** Without `xsettingsd` installed, everything except
  "already-running GTK/Qt apps" still works. That layer degrades on its own.
- **At 96 DPI nothing changes.** Every scale factor is `dpi / 96`, so a default
  session renders byte-identically to today. That is the property that makes
  this safe to land.

### Why XSETTINGS and not `gsettings text-scaling-factor`

`org.gnome.desktop.interface text-scaling-factor` is a *multiplier applied on top
of* whatever DPI the toolkit already resolved. Setting both it and `Xft.dpi`
double-scales. XSETTINGS `Xft/DPI` replaces the value outright and is what both
GTK and the Qt xcb platform plugin watch at runtime, so it is the single correct
channel. `scripts/theme-apply.sh:592` already writes GSettings keys for theme and
cursor; deliberately not adding a DPI key there keeps the two from fighting.

### Deliberately out of scope

- **`Xcursor.size`.** Cursor size is owned by Appearance
  (`$XDG_CONFIG_HOME/lyona/cursor.Xresources`, watched at
  `AppearanceModel.qml:185`). Having the display helper also write it would be
  exactly the "overwriting unrelated toolkit configuration" that
  `AGENTS.md` rules out. If DPI-aware cursors are wanted, they belong in the
  appearance helper reading the published DPI record from §3.5.
- **Resetting the server DPI on `dpi-reset`.** `xrandr --dpi` has no inverse; the
  physically-correct value would have to be recomputed from
  `recommended_dpi()`. `dpi-reset` therefore clears the resource and the
  XSETTINGS key but leaves the server DPI where it is until the next session.
  Called out in §8 as a known gap rather than papered over.

---

## 3. `scripts/dwm-settings-display`

### 3.1 New configuration variable

**Find** (`scripts/dwm-settings-display:7`–`:14`):

```bash
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/lyona"
profile_dir="${DWM_DISPLAY_PROFILE_DIR:-$config_dir/display-profiles}"
dpi_resources="${DWM_DPI_RESOURCES:-$config_dir/dpi.Xresources}"
minimum_dpi=72
maximum_dpi=384
runtime_base="${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}"
state_dir="$runtime_base/dwm-settings-display"
managed_config="${DWM_XORG_CONFIG:-/etc/X11/xorg.conf.d/90-lyona-display.conf}"
```

**Replace with:**

```bash
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/lyona"
profile_dir="${DWM_DISPLAY_PROFILE_DIR:-$config_dir/display-profiles}"
dpi_resources="${DWM_DPI_RESOURCES:-$config_dir/dpi.Xresources}"
xsettings_config="${DWM_XSETTINGS_CONFIG:-$config_dir/xsettingsd.conf}"
default_dpi=96
minimum_dpi=72
maximum_dpi=384
runtime_base="${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}"
state_dir="$runtime_base/dwm-settings-display"
dpi_state="$state_dir/dpi.current"
managed_config="${DWM_XORG_CONFIG:-/etc/X11/xorg.conf.d/90-lyona-display.conf}"
```

`DWM_XSETTINGS_CONFIG` mirrors the existing `DWM_DPI_RESOURCES` override so
`tests/test-settings.sh` can redirect it into a scratch directory.

---

### 3.2 Replace the whole DPI mutation block

**Find** (`scripts/dwm-settings-display:227`–`:269`, from `merge_dpi()` through
the end of `apply_saved_dpi()`):

```bash
merge_dpi() {
	local value=$1
	x11_resources_available || return 0
	printf 'Xft.dpi: %s\n' "$value" | xrdb -merge 2>/dev/null ||
		printf 'dwm-settings-display: could not merge Xft.dpi into the running X resource database\n' >&2
}

set_dpi() {
	local value=$1 temporary
	valid_dpi "$value" ||
		die "DPI must be an integer between $minimum_dpi and $maximum_dpi"
	[[ ! -L $dpi_resources ]] || die "refusing to write through a symlinked DPI resource file"
	mkdir -p "$config_dir"
	temporary=$(mktemp "$config_dir/.dpi.XXXXXX")
	trap 'rm -f "${temporary:-}"' RETURN
	printf 'Xft.dpi: %s\n' "$value" >"$temporary"
	chmod 644 "$temporary"
	mv -fT "$temporary" "$dpi_resources"
	temporary=
	merge_dpi "$value"
	printf 'result\tdpi-set\t%s\n' "$value"
}

reset_dpi() {
	local remaining
	[[ ! -L $dpi_resources ]] || die "refusing to remove a symlinked DPI resource file"
	rm -f "$dpi_resources"
	if x11_resources_available; then
		remaining=$(mktemp)
		trap 'rm -f "${remaining:-}"' RETURN
		if xrdb -query >"$remaining" 2>/dev/null; then
			awk -F: '$1 != "Xft.dpi"' "$remaining" | xrdb -load 2>/dev/null ||
				printf 'dwm-settings-display: could not clear Xft.dpi from the running X resource database\n' >&2
		fi
	fi
	printf 'result\tdpi-reset\tdefault\n'
}

apply_saved_dpi() {
	local value
	value=$(persisted_dpi) || return 0
	merge_dpi "$value"
}
```

**Replace with:**

```bash
warn() {
	printf 'dwm-settings-display: %s\n' "$*" >&2
}

merge_dpi() {
	local value=$1
	x11_resources_available || return 0
	printf 'Xft.dpi: %s\n' "$value" | xrdb -merge 2>/dev/null ||
		warn "could not merge Xft.dpi into the running X resource database"
}

clear_merged_dpi() {
	local remaining
	x11_resources_available || return 0
	remaining=$(mktemp)
	trap 'rm -f "${remaining:-}"' RETURN
	if xrdb -query >"$remaining" 2>/dev/null; then
		awk -F: '$1 != "Xft.dpi"' "$remaining" | xrdb -load 2>/dev/null ||
			warn "could not clear Xft.dpi from the running X resource database"
	fi
}

# The X server's own idea of the screen DPI, for the clients that measure the
# screen instead of reading a resource -- Electron and some JVM toolkits. Best
# effort: some drivers refuse this outside a mode-setting operation, and a
# refusal must not fail the DPI change.
apply_server_dpi() {
	local value=$1
	command -v xrandr >/dev/null 2>&1 && [[ -n ${DISPLAY:-} ]] || return 0
	xrandr --dpi "$value" >/dev/null 2>&1 ||
		warn "the X server refused a DPI change; running clients keep the old screen size"
}

# XSETTINGS is the only channel that rescales an *already running* GTK or Qt
# client. Both watch Xft/DPI, expressed in 1024ths, and xsettingsd re-reads its
# configuration on SIGHUP and pushes the new value to every connected client.
#
# Unrelated keys survive: the file is filtered, never rewritten wholesale, so a
# user or a future helper can own other settings in the same file.
write_xsettings_dpi() {
	local value=$1 temporary
	command -v xsettingsd >/dev/null 2>&1 || return 0
	if [[ -L $xsettings_config ]]; then
		warn "refusing to write through a symlinked xsettingsd configuration"
		return 0
	fi
	mkdir -p "$config_dir" || return 0
	temporary=$(mktemp "$config_dir/.xsettingsd.XXXXXX") || return 0
	trap 'rm -f "${temporary:-}"' RETURN
	if [[ -f $xsettings_config ]]; then
		grep -v '^[[:space:]]*Xft/DPI[[:space:]]' "$xsettings_config" >"$temporary" || :
	fi
	if [[ -n $value ]]; then
		printf 'Xft/DPI %s\n' "$((10#$value * 1024))" >>"$temporary"
	fi
	chmod 644 "$temporary"
	mv -fT "$temporary" "$xsettings_config" || return 0
	temporary=
	# A missing or not-yet-started daemon is fine; it reads the file on start.
	pkill -HUP -u "$UID" -x xsettingsd >/dev/null 2>&1 || :
}

# A two-line tab-separated record the Quickshell shell watches with a FileView.
# The shell has no way to read RESOURCE_MANAGER and no reason to poll xrdb, so
# the helper hands it the active value directly. Written through a rename so a
# reader never sees a half-written file.
publish_dpi_state() {
	local value=$1 temporary
	[[ -d $runtime_base && ! -L $runtime_base ]] || return 0
	if [[ ! -e $state_dir ]]; then
		mkdir -m 700 "$state_dir" 2>/dev/null || return 0
	fi
	[[ -d $state_dir && ! -L $state_dir ]] || return 0
	temporary=$(mktemp "$state_dir/.dpi.XXXXXX" 2>/dev/null) || return 0
	printf 'dpi-state-protocol\t1\ndpi\t%s\n' "$value" >"$temporary"
	chmod 600 "$temporary"
	mv -fT "$temporary" "$dpi_state" 2>/dev/null || rm -f "$temporary"
}

# Everything that has to happen for a DPI change to be visible in the session
# that made it. Ordered cheapest-blast-radius first so a failure late in the
# list still leaves the session consistent with what was persisted.
apply_dpi_runtime() {
	local value=$1

	merge_dpi "$value"
	write_xsettings_dpi "$value"
	apply_server_dpi "$value"
	publish_dpi_state "$value"
}

set_dpi() {
	local value=$1 temporary
	valid_dpi "$value" ||
		die "DPI must be an integer between $minimum_dpi and $maximum_dpi"
	[[ ! -L $dpi_resources ]] || die "refusing to write through a symlinked DPI resource file"
	mkdir -p "$config_dir"
	temporary=$(mktemp "$config_dir/.dpi.XXXXXX")
	trap 'rm -f "${temporary:-}"' RETURN
	printf 'Xft.dpi: %s\n' "$value" >"$temporary"
	chmod 644 "$temporary"
	mv -fT "$temporary" "$dpi_resources"
	temporary=
	apply_dpi_runtime "$value"
	printf 'result\tdpi-set\t%s\n' "$value"
}

reset_dpi() {
	[[ ! -L $dpi_resources ]] || die "refusing to remove a symlinked DPI resource file"
	rm -f "$dpi_resources"
	clear_merged_dpi
	# Drop the key rather than pinning 96, so clients fall back to whatever the
	# server reports. The published record still names the effective value,
	# which is what emit_dpi reports as "default".
	write_xsettings_dpi ""
	publish_dpi_state "$default_dpi"
	printf 'result\tdpi-reset\tdefault\n'
}

apply_saved_dpi() {
	local value
	if ! value=$(persisted_dpi); then
		publish_dpi_state "$(session_dpi || printf '%s' "$default_dpi")"
		return 0
	fi
	apply_dpi_runtime "$value"
}
```

**Notes**

- `dpi-set`, `dpi-reset` and `dpi-apply-saved` keep their exact stdout
  protocol (`result\tdpi-set\tN`, `result\tdpi-reset\tdefault`, silence), so
  `SettingsModel.qml` and `tests/test-settings.sh:333`-onward need no change.
- `apply_saved_dpi` now publishes a record even when nothing is saved. Without
  that, the shell would start with no file to read and would have to guess.
- `warn()` replaces the two open-coded `printf ... >&2` calls; it is added
  rather than reusing `die()` because none of these layers should abort the
  action.
- `grep -v` exits 1 when it prints nothing, which under `set -e` would abort —
  hence `|| :`.
- `publish_dpi_state` creates the directory with a bare `mkdir -m 700` guarded
  by an existence test rather than `mkdir -m 700 -p`, matching
  `ensure_state_dir()` (`scripts/dwm-settings-display:65`). With `-p`, `-m`
  applies only to the deepest component, which is shellcheck SC2174 and a real
  permissions hole on the parent.
- Aside: `scripts/dwm-settings-display` and `scripts/dwm-settings-input` are
  absent from the `check-shell` file list (`Makefile:344`) — they have no `.sh`
  extension and are not named explicitly, so shellcheck never sees them. Worth
  adding while this branch is open.

---

## 4. `dwm.c`

dwm draws borders and measures a snap distance in raw pixels and has never read
`Xft.dpi`. At 192 DPI a 1px border is invisible and the 32px snap threshold is
half the distance it should be.

dwm already selects `PropertyChangeMask` on the root window (`dwm.c:4117`), so
the `RESOURCE_MANAGER` change `xrdb` makes arrives as a `PropertyNotify` with no
new event mask, no polling, and no new file watch.

### 4.1 Include

**Find** (`dwm.c:45`):

```c
#include <X11/Xproto.h>
```

**Replace with:**

```c
#include <X11/Xproto.h>
#include <X11/Xresource.h>
```

No linker change: `XrmGetStringDatabase` and friends are in `libX11`, which
`config.mk` already links via the `x11` pkg-config module.

### 4.2 Forward declarations

**Find** (`dwm.c:246`–`dwm.c:247`):

```c
static void restackprioritywindows(void);
static void restack(Monitor *m);
```

**Replace with:**

```c
static void restackprioritywindows(void);
static void restack(Monitor *m);
static unsigned int scaledpx(unsigned int value);
static void updatefonts(void);
static void updatedpi(int force);
```

### 4.3 State

**Find** (`dwm.c:435`):

```c
static unsigned int  dyn_borderpx;
```

**Replace with:**

```c
#define DEFAULTDPI 96
#define MINDPI     72
#define MAXDPI     384

static unsigned int  dyn_borderpx;
/* The unscaled border width as themes.toml states it. dyn_borderpx is this
 * value scaled to the active DPI, so a config reload and a DPI change can each
 * recompute without clobbering what the other one meant. */
static unsigned int  cfg_borderpx = 1;
static unsigned int  dyn_snap;
static int           dpi_value = DEFAULTDPI;
```

`MINDPI`/`MAXDPI` intentionally match the 72–384 range the helper validates
(`scripts/dwm-settings-display:146`) and the Settings pane enforces
(`SettingsModel.qml:81`).

### 4.4 The three new functions

Add these immediately before `void setup(void)` (`dwm.c:4004`):

```c
/* Scale a pixel measurement that config states at 96 DPI. Rounds to nearest,
 * and never lets a feature that is meant to be visible round away to zero --
 * but a deliberate 0 (no border, no gap) stays 0. */
unsigned int
scaledpx(unsigned int value)
{
	if (value == 0)
		return 0;
	return MAX(1u, (value * (unsigned int)dpi_value + DEFAULTDPI / 2) / DEFAULTDPI);
}

/* Reopen the fontset at the active DPI.
 *
 * The DPI has to go into the fontconfig pattern explicitly. Xft resolves a
 * point size against the resource database it cached when the display was
 * first used, so merely rewriting RESOURCE_MANAGER and reopening the font
 * hands back the size it resolved at start-up. A pattern that already states
 * an absolute pixelsize (the emoji fallback) is left alone -- fontconfig
 * ignores dpi there, and appending it would only make the pattern noisier.
 *
 * The old fontset is kept if the new one cannot be built, so a bad DPI never
 * leaves dwm unable to measure text. */
void
updatefonts(void)
{
	char scaled[LENGTH(fonts)][256];
	const char *names[LENGTH(fonts)];
	Fnt *previous;
	size_t i;

	if (!drw)
		return;

	for (i = 0; i < LENGTH(fonts); i++) {
		if (strstr(fonts[i], "pixelsize="))
			snprintf(scaled[i], sizeof scaled[i], "%s", fonts[i]);
		else
			snprintf(scaled[i], sizeof scaled[i], "%s:dpi=%d", fonts[i], dpi_value);
		names[i] = scaled[i];
	}

	previous = drw->fonts;
	drw->fonts = NULL;
	if (!drw_fontset_create(drw, names, LENGTH(fonts))) {
		drw->fonts = previous;
		fprintf(stderr, "dwm: could not reload fonts at %d dpi\n", dpi_value);
		return;
	}
	drw_fontset_free(previous);
	lrpad = drw->fonts->h;
}

/* Read Xft.dpi out of the root RESOURCE_MANAGER property -- the property
 * `xrdb -merge` rewrites -- and rescale everything dwm sizes in pixels.
 *
 * Returns early when the value has not moved, because the root window sees
 * PropertyNotify traffic for reasons that have nothing to do with resources
 * and this must stay cheap. Pass force = 1 from setup(), where dpi_value is
 * still at its initial value but nothing has been scaled yet. */
void
updatedpi(int force)
{
	char *resources;
	char *type = NULL;
	XrmDatabase db;
	XrmValue value;
	int parsed, newdpi = DEFAULTDPI;
	unsigned int newborder;
	Monitor *m;
	Client *c;

	if (!dpy)
		return;

	if ((resources = XResourceManagerString(dpy))) {
		if ((db = XrmGetStringDatabase(resources))) {
			if (XrmGetResource(db, "Xft.dpi", "Xft.Dpi", &type, &value)
			    && value.addr) {
				parsed = atoi(value.addr);
				if (parsed >= MINDPI && parsed <= MAXDPI)
					newdpi = parsed;
			}
			XrmDestroyDatabase(db);
		}
	}

	if (!force && newdpi == dpi_value)
		return;
	dpi_value = newdpi;

	updatefonts();
	dyn_snap = scaledpx(snap);

	newborder = scaledpx(cfg_borderpx);
	if (newborder != dyn_borderpx) {
		dyn_borderpx = newborder;
		for (m = mons; m; m = m->next)
			for (c = m->clients; c; c = c->next) {
				/* A fullscreen client parks its real border in oldbw and
				 * draws none; setfullscreen() restores from there. */
				if (c->isfullscreen && c->fakefullscreen != 1) {
					c->oldbw = dyn_borderpx;
					continue;
				}
				c->bw = dyn_borderpx;
				XSetWindowBorderWidth(dpy, c->win, c->bw);
			}
	}

	if (mons) {
		arrange(NULL);
		restackprioritywindows();
	}
	fprintf(stderr, "dwm: display scale is now %d dpi\n", dpi_value);
}
```

### 4.5 React to the resource-database change

**Find** (`dwm.c:2338`–`dwm.c:2341`):

```c
	if ((ev->window == root) && (ev->atom == XA_WM_NAME)) {
		updatestatus();
	} else if (ev->state == PropertyDelete) {
		return;
```

**Replace with:**

```c
	if ((ev->window == root) && (ev->atom == XA_WM_NAME)) {
		updatestatus();
	} else if ((ev->window == root) && (ev->atom == XA_RESOURCE_MANAGER)) {
		/* xrdb -merge / -load rewrites this property; it is how a DPI change
		 * reaches dwm without a signal, a poll or a second file watch. */
		updatedpi(0);
	} else if (ev->state == PropertyDelete) {
		return;
```

`XA_RESOURCE_MANAGER` is a predefined atom from `<X11/Xatom.h>`, already
included at `dwm.c:43`.

### 4.6 Pick the DPI up at start-up

**Find** (`dwm.c:4021`–`dwm.c:4025`):

```c
	drw = drw_create(dpy, screen, root, sw, sh);
	if (!drw_fontset_create(drw, fonts, LENGTH(fonts)))
		die("no fonts could be loaded.");
	lrpad = drw->fonts->h;
	bh = 0;
```

**Replace with:**

```c
	drw = drw_create(dpy, screen, root, sw, sh);
	if (!drw_fontset_create(drw, fonts, LENGTH(fonts)))
		die("no fonts could be loaded.");
	lrpad = drw->fonts->h;
	dyn_snap = snap;
	/* autostart.sh runs `dpi-apply-saved` before dwm's first arrange, so the
	 * saved value is already in RESOURCE_MANAGER by the time we get here. */
	updatedpi(1);
	bh = 0;
```

At this point `mons` is still `NULL`, so `updatedpi()` only sets the scalars and
reopens the fontset — the client loop and `arrange()` are skipped.

### 4.7 Keep the config-supplied border width unscaled

**Find** (`dwm.c:3734`–`dwm.c:3748`):

```c
	const TomlValue *vbpx = toml_get(&doc, "appearance", "borderpx");
	if (vbpx && vbpx->type == TOML_INT && vbpx->i >= 0) {
		unsigned int newbpx = (unsigned int)vbpx->i;
		if (newbpx != dyn_borderpx) {
			dyn_borderpx = newbpx;
			if (mons) {
				Monitor *m;
				Client  *c;
				for (m = mons; m; m = m->next)
					for (c = m->clients; c; c = c->next) {
						c->bw = dyn_borderpx;
						XSetWindowBorderWidth(dpy, c->win, c->bw);
					}
			}
		}
	}
```

**Replace with:**

```c
	const TomlValue *vbpx = toml_get(&doc, "appearance", "borderpx");
	if (vbpx && vbpx->type == TOML_INT && vbpx->i >= 0) {
		unsigned int newbpx;
		/* themes.toml states the border at 96 dpi; keep it so updatedpi() can
		 * rescale from the authored value instead of from a scaled one. */
		cfg_borderpx = (unsigned int)vbpx->i;
		newbpx = scaledpx(cfg_borderpx);
		if (newbpx != dyn_borderpx) {
			dyn_borderpx = newbpx;
			if (mons) {
				Monitor *m;
				Client  *c;
				for (m = mons; m; m = m->next)
					for (c = m->clients; c; c = c->next) {
						if (c->isfullscreen && c->fakefullscreen != 1) {
							c->oldbw = dyn_borderpx;
							continue;
						}
						c->bw = dyn_borderpx;
						XSetWindowBorderWidth(dpy, c->win, c->bw);
					}
			}
		}
	}
```

### 4.8 Optional — scale the snap distance

`snap` is `static const unsigned int snap = 32;` (`config.def.h:6`), used at
seven call sites. `dyn_snap` from §4.3 is already computed; this swaps the uses
over. Skip this section if you would rather keep the diff to borders only —
nothing else depends on it.

**`dwm.c:2082`–`dwm.c:2092`, in `movemouse()`. Find:**

```c
			if (abs(selmon->wx - nx) < snap)
				nx = selmon->wx;
			else if (abs((selmon->wx + selmon->ww) - (nx + WIDTH(c))) < snap)
				nx = selmon->wx + selmon->ww - WIDTH(c);
			if (abs(selmon->wy - ny) < snap)
				ny = selmon->wy;
			else if (abs((selmon->wy + selmon->wh) - (ny + HEIGHT(c))) < snap)
				ny = selmon->wy + selmon->wh - HEIGHT(c);
			if (!c->isfloating && selmon->lt[selmon->sellt]->arrange
			&& (abs(nx - c->x) > snap || abs(ny - c->y) > snap))
				togglefloating(NULL);
```

**Replace with:**

```c
			if (abs(selmon->wx - nx) < (int)dyn_snap)
				nx = selmon->wx;
			else if (abs((selmon->wx + selmon->ww) - (nx + WIDTH(c))) < (int)dyn_snap)
				nx = selmon->wx + selmon->ww - WIDTH(c);
			if (abs(selmon->wy - ny) < (int)dyn_snap)
				ny = selmon->wy;
			else if (abs((selmon->wy + selmon->wh) - (ny + HEIGHT(c))) < (int)dyn_snap)
				ny = selmon->wy + selmon->wh - HEIGHT(c);
			if (!c->isfloating && selmon->lt[selmon->sellt]->arrange
			&& (abs(nx - c->x) > (int)dyn_snap || abs(ny - c->y) > (int)dyn_snap))
				togglefloating(NULL);
```

**`dwm.c:2233`, in `resizemouse()`. Find:**

```c
			if (!freemove && (abs(nx - ocx) > snap || abs(ny - ocy) > snap))
```

**Replace with:**

```c
			if (!freemove && (abs(nx - ocx) > (int)dyn_snap || abs(ny - ocy) > (int)dyn_snap))
```

**`dwm.c:2497`, in `resizetiledmouse()`. Find:**

```c
				&& (abs(nw - c->w) > snap || abs(nh - c->h) > snap)) {
```

**Replace with:**

```c
				&& (abs(nw - c->w) > (int)dyn_snap || abs(nh - c->h) > (int)dyn_snap)) {
```

The `(int)` casts are what the original comparisons already did implicitly via
integer promotion of the `const unsigned int`; making them explicit keeps
`-Wall -pedantic` quiet about the signed/unsigned comparison.

---

## 5. `config/quickshell/core/Theme.qml`

The panel and every popup size themselves from hard-coded pixel constants here,
so the shell is the one surface that stays the same physical size no matter what
DPI the session is at.

The change adds `displayDpi`, derives `uiScale` from it, and routes every pixel
metric through a `dp()` helper. **At 96 DPI `uiScale` is 1 and `dp(n)` returns
`n`, so the rendered result is unchanged.**

Two things deliberately do *not* scale: `animationFast` / `animationNormal` are
durations in milliseconds, and `fontScale` stays a separate user-controlled
multiplier that composes with `uiScale` rather than being replaced by it.

### 5.1 Add the scale

**Find** (`Theme.qml:80`–`:87`):

```qml
    property string fontFamily: "MesloLGS Nerd Font Mono"
    property real fontScale: 1.0
    readonly property string iconFontFamily: "MesloLGS Nerd Font Mono"

    function applyFontPreferences(family, scale) {
        root.fontFamily = family.length > 0 ? family : "MesloLGS Nerd Font Mono";
        root.fontScale = Math.max(0.8, Math.min(1.5, scale));
    }
```

**Replace with:**

```qml
    property string fontFamily: "MesloLGS Nerd Font Mono"
    property real fontScale: 1.0
    readonly property string iconFontFamily: "MesloLGS Nerd Font Mono"

    function applyFontPreferences(family, scale) {
        root.fontFamily = family.length > 0 ? family : "MesloLGS Nerd Font Mono";
        root.fontScale = Math.max(0.8, Math.min(1.5, scale));
    }

    /*
     * The session's active Xft DPI, published by `dwm-settings-display` and
     * watched in shell.qml. Every metric below is authored at 96 DPI and
     * multiplied through dp(), so uiScale === 1 reproduces the previous
     * pixel-for-pixel layout exactly.
     *
     * fontScale stays independent: it is the user's text-size preference and
     * composes with uiScale rather than replacing it.
     */
    property int displayDpi: 96
    readonly property real uiScale: Math.max(0.75, Math.min(3.0, root.displayDpi / 96))

    function applyDisplayDpi(dpi) {
        const value = Math.round(Number(dpi));
        root.displayDpi = (isFinite(value) && value >= 72 && value <= 384) ? value : 96;
    }

    /* A zero stays zero -- a metric set to 0 means "no border/no margin", not
     * "the smallest possible one". Everything else keeps at least one pixel. */
    function dp(px) {
        if (px <= 0)
            return 0;
        return Math.max(1, Math.round(px * root.uiScale));
    }
```

### 5.2 Scale the metrics

**Find** (`Theme.qml:89`–`:171`, from `spacingXxs` through `closeButtonSize`):

```qml
    readonly property int spacingXxs: 2
    readonly property int spacingXs: 3
    readonly property int spacingSm: 4
    readonly property int spacingMd: 6
    readonly property int spacingLg: 8
    readonly property int spacingXl: 10
    readonly property int spacingXxl: 12
    readonly property int spacingXxxl: 14
    readonly property int spacingHuge: 18

    readonly property int fontCaptionSize: Math.max(8, Math.round(10 * fontScale))
    readonly property int fontBodySmallSize: Math.max(10, Math.round(12 * fontScale))
    readonly property int fontBodySize: Math.max(10, Math.round(13 * fontScale))
    readonly property int fontSubtitleSize: Math.max(11, Math.round(14 * fontScale))
    readonly property int fontTitleSize: Math.max(14, Math.round(18 * fontScale))
    readonly property int largeSurfaceTitleSize: Math.max(18, Math.round(24 * fontScale))
    readonly property int panelIconFontSize: 13

    readonly property int controlHeight: 30
    readonly property int controlRowHeight: 32
    readonly property int controlPaddingX: 9
    readonly property int controlBorderWidth: 1
    readonly property int controlFocusBorderWidth: 2
    readonly property int controlRadius: 6
    readonly property int menuHeaderHeight: 26
    readonly property int popupPadding: spacingHuge
    readonly property int popupRadius: controlRadius
    readonly property int panelHeroIconSize: 32
    readonly property real panelMetaLetterSpacing: 1.2
    readonly property int panelSliderHeight: 32
    readonly property int panelSliderTrackHeight: 6
    readonly property int panelSliderKnobSize: 16
    readonly property int panelToggleWidth: 40
    readonly property int panelToggleHeight: 22
    readonly property int panelToggleKnobSize: 14
    readonly property int panelToggleInset: 3

    readonly property int panelHeight: 30
    readonly property int panelMargin: 0
    readonly property int panelEdgeMargin: 0
    readonly property int panelGap: spacingSm
    readonly property int popupMargin: popupPadding
    readonly property int popupSpacing: spacingXxl
    readonly property int controlCenterX: 6
    readonly property int controlCenterWidth: 276
    readonly property int rowSpacing: spacingXl
    readonly property int listSpacing: spacingSm
    readonly property int compactSpacing: spacingXxs
    readonly property int tightSpacing: spacingXs
    readonly property int sectionSpacing: spacingXxxl
    readonly property int radius: controlRadius
    readonly property int smallRadius: controlRadius
    readonly property int barRadius: 0
    readonly property int pillRadius: 6
    readonly property int pillHeight: 26
    readonly property int pillHorizontalPadding: 9
    readonly property int compactWidgetSize: 22
    readonly property int compactWidgetHorizontalPadding: 6
    readonly property real networkWidgetHorizontalPadding: 4.5
    readonly property int pillBorderWidth: controlBorderWidth
    readonly property int animationFast: 120
    readonly property int animationNormal: 180
    readonly property int buttonHeight: controlHeight
    readonly property int chipHeight: 28
    readonly property int workspaceButtonSize: 22
    readonly property int compactButtonHeight: 40
    readonly property int confirmButtonHeight: 48
    readonly property int notificationAccentWidth: 4
    readonly property int notificationAccentRadius: 2
    readonly property int largeSurfaceMargin: 22
    readonly property int largeSurfaceNavWidth: 248
    readonly property int largeSurfaceSearchHeight: 44
    readonly property int largeSurfaceCardRadius: 8
    readonly property int titleFontSize: fontTitleSize
    readonly property int bodyFontSize: fontSubtitleSize
    readonly property int panelFontSize: fontBodySize
    readonly property int smallFontSize: fontBodySmallSize
    readonly property int tinyFontSize: fontCaptionSize
    readonly property int inputFontSize: Math.max(12, Math.round(16 * fontScale))
    readonly property int iconSize: 28
    readonly property int trayItemSize: 24
    readonly property int trayIconSize: 18
    readonly property int closeButtonSize: 30
```

**Replace with:**

```qml
    readonly property int spacingXxs: dp(2)
    readonly property int spacingXs: dp(3)
    readonly property int spacingSm: dp(4)
    readonly property int spacingMd: dp(6)
    readonly property int spacingLg: dp(8)
    readonly property int spacingXl: dp(10)
    readonly property int spacingXxl: dp(12)
    readonly property int spacingXxxl: dp(14)
    readonly property int spacingHuge: dp(18)

    readonly property int fontCaptionSize: Math.max(dp(8), Math.round(10 * fontScale * uiScale))
    readonly property int fontBodySmallSize: Math.max(dp(10), Math.round(12 * fontScale * uiScale))
    readonly property int fontBodySize: Math.max(dp(10), Math.round(13 * fontScale * uiScale))
    readonly property int fontSubtitleSize: Math.max(dp(11), Math.round(14 * fontScale * uiScale))
    readonly property int fontTitleSize: Math.max(dp(14), Math.round(18 * fontScale * uiScale))
    readonly property int largeSurfaceTitleSize: Math.max(dp(18), Math.round(24 * fontScale * uiScale))
    readonly property int panelIconFontSize: dp(13)

    readonly property int controlHeight: dp(30)
    readonly property int controlRowHeight: dp(32)
    readonly property int controlPaddingX: dp(9)
    readonly property int controlBorderWidth: dp(1)
    readonly property int controlFocusBorderWidth: dp(2)
    readonly property int controlRadius: dp(6)
    readonly property int menuHeaderHeight: dp(26)
    readonly property int popupPadding: spacingHuge
    readonly property int popupRadius: controlRadius
    readonly property int panelHeroIconSize: dp(32)
    readonly property real panelMetaLetterSpacing: 1.2 * uiScale
    readonly property int panelSliderHeight: dp(32)
    readonly property int panelSliderTrackHeight: dp(6)
    readonly property int panelSliderKnobSize: dp(16)
    readonly property int panelToggleWidth: dp(40)
    readonly property int panelToggleHeight: dp(22)
    readonly property int panelToggleKnobSize: dp(14)
    readonly property int panelToggleInset: dp(3)

    readonly property int panelHeight: dp(30)
    readonly property int panelMargin: 0
    readonly property int panelEdgeMargin: 0
    readonly property int panelGap: spacingSm
    readonly property int popupMargin: popupPadding
    readonly property int popupSpacing: spacingXxl
    readonly property int controlCenterX: dp(6)
    readonly property int controlCenterWidth: dp(276)
    readonly property int rowSpacing: spacingXl
    readonly property int listSpacing: spacingSm
    readonly property int compactSpacing: spacingXxs
    readonly property int tightSpacing: spacingXs
    readonly property int sectionSpacing: spacingXxxl
    readonly property int radius: controlRadius
    readonly property int smallRadius: controlRadius
    readonly property int barRadius: 0
    readonly property int pillRadius: dp(6)
    readonly property int pillHeight: dp(26)
    readonly property int pillHorizontalPadding: dp(9)
    readonly property int compactWidgetSize: dp(22)
    readonly property int compactWidgetHorizontalPadding: dp(6)
    readonly property real networkWidgetHorizontalPadding: 4.5 * uiScale
    readonly property int pillBorderWidth: controlBorderWidth
    readonly property int animationFast: 120
    readonly property int animationNormal: 180
    readonly property int buttonHeight: controlHeight
    readonly property int chipHeight: dp(28)
    readonly property int workspaceButtonSize: dp(22)
    readonly property int compactButtonHeight: dp(40)
    readonly property int confirmButtonHeight: dp(48)
    readonly property int notificationAccentWidth: dp(4)
    readonly property int notificationAccentRadius: dp(2)
    readonly property int largeSurfaceMargin: dp(22)
    readonly property int largeSurfaceNavWidth: dp(248)
    readonly property int largeSurfaceSearchHeight: dp(44)
    readonly property int largeSurfaceCardRadius: dp(8)
    readonly property int titleFontSize: fontTitleSize
    readonly property int bodyFontSize: fontSubtitleSize
    readonly property int panelFontSize: fontBodySize
    readonly property int smallFontSize: fontBodySmallSize
    readonly property int tinyFontSize: fontCaptionSize
    readonly property int inputFontSize: Math.max(dp(12), Math.round(16 * fontScale * uiScale))
    readonly property int iconSize: dp(28)
    readonly property int trayItemSize: dp(24)
    readonly property int trayIconSize: dp(18)
    readonly property int closeButtonSize: dp(30)
```

`animationFast` and `animationNormal` are the only two integers left unwrapped
on purpose — they are milliseconds, not pixels.

> **Check before merging:** the panel's own window height comes from
> `Theme.panelHeight`, and dwm adopts that height as `m->bh` at `dwm.c:4785`
> (`newbh = wa->height > 0 ? wa->height : bh`). When the panel resizes itself
> after a DPI change, dwm picks the new height up from the resulting
> `ConfigureNotify` and `updatebarpos()` reserves the right strut. Confirm this
> on a live session — it is the one interaction in this change that spans both
> processes.

---

## 6. `config/quickshell/shell.qml`

The shell needs to hear about the DPI change. `SettingsModel` already parses a
`dpi` record, but only when the Settings pane refreshes, so it is the wrong
source for the panel. Watch the runtime record §3.2 publishes instead.

### 6.1 Import

**Find** (`shell.qml:1`–`:4`):

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
```

**Replace with:**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.core
```

`Quickshell.Io` (already imported) provides `FileView`; `qs.core` provides the
`Theme` singleton.

### 6.2 The watcher

**Find** (`shell.qml:173`–`:175`):

```qml
    AppearanceModel {
        id: appearanceModel
    }
```

**Replace with:**

```qml
    AppearanceModel {
        id: appearanceModel
    }

    /*
     * The active Xft DPI, published by `dwm-settings-display` on every dpi-set,
     * dpi-reset and dpi-apply-saved. autostart.sh runs dpi-apply-saved before
     * the shell starts, so the file is already there on a normal session; a
     * missing or malformed file leaves Theme at its 96 DPI default.
     *
     * XDG_RUNTIME_DIR is always set in a systemd session, which is the only way
     * this shell starts; without it the helper falls back to /tmp/lyona-$UID
     * and the shell simply keeps its default rather than guessing a uid it
     * cannot read from the environment.
     */
    readonly property string dpiStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "")
        + "/dwm-settings-display/dpi.current"

    function applyDpiState(text) {
        let dpi = 96;
        let valid = false;
        for (const line of String(text).trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "dpi-state-protocol" && fields[1] === "1") {
                valid = true;
            } else if (fields[0] === "dpi" && fields.length >= 2) {
                dpi = Number(fields[1]);
            }
        }
        if (valid)
            Theme.applyDisplayDpi(dpi);
    }

    FileView {
        id: dpiStateWatch
        path: root.dpiStatePath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyDpiState(this.text())
        onFileChanged: reload()
    }
```

The `onLoadFailed` handler is deliberately omitted: a missing file should leave
`Theme.displayDpi` at its default rather than reset it, and `printErrors: false`
keeps it quiet — the same shape as the `FileView` blocks at
`AppearanceModel.qml:1452`-onward.

> **Confirm before merging:** nothing in this repo currently reads a
> `FileView`'s contents directly — every existing one either uses a
> `JsonAdapter` (`NotificationModel.qml:151`) or treats `onLoaded` purely as a
> change trigger and re-runs a helper `Process`
> (`AppearanceModel.qml:1452`-onward). `FileView.text()` is Quickshell's
> documented reader, but check it against the pinned Quickshell version with
> `scripts/quickshell-qmllint` first. If it does not resolve, fall back to the
> repo's established shape: keep the `FileView` as the watch and have `onLoaded`
> trigger a `Process` running `dwm-settings-display discover`, parsing the `dpi`
> record `emit_dpi()` already emits.

---

## 7. Session start-up and packaging

### 7.1 `scripts/autostart.sh`

`xsettingsd` has to be running before `dpi-apply-saved` sends it a `SIGHUP`,
otherwise the saved DPI reaches everything except already-running clients on the
first session.

**Find** (`scripts/autostart.sh:396`–`:401`):

```sh
if [ -z "$display_helper" ] && command -v dwm-settings-display >/dev/null 2>&1; then
	display_helper=dwm-settings-display
fi
if [ -n "$display_helper" ]; then
	"$display_helper" dpi-apply-saved >/dev/null 2>&1 || true
fi
```

**Replace with:**

```sh
if [ -z "$display_helper" ] && command -v dwm-settings-display >/dev/null 2>&1; then
	display_helper=dwm-settings-display
fi

# The XSETTINGS manager is what lets a later DPI change rescale GTK and Qt
# clients that are already open. It has to be up before dpi-apply-saved so the
# saved value is in the file it reads at start-up. Optional: without it the
# session still gets the right DPI, it just needs a restart per app to change.
if command -v xsettingsd >/dev/null 2>&1 &&
	! pgrep -u "$(id -u)" -x xsettingsd >/dev/null 2>&1; then
	if [ "${DWM_AUTOSTART_NO_SETSID:-0}" != 1 ] && command -v setsid >/dev/null 2>&1; then
		setsid -f xsettingsd -c "${XDG_CONFIG_HOME:-$HOME/.config}/lyona/xsettingsd.conf" \
			>/dev/null 2>&1 || true
	else
		xsettingsd -c "${XDG_CONFIG_HOME:-$HOME/.config}/lyona/xsettingsd.conf" \
			>/dev/null 2>&1 &
	fi
fi

if [ -n "$display_helper" ]; then
	"$display_helper" dpi-apply-saved >/dev/null 2>&1 || true
fi
```

`xsettingsd` exits immediately if another XSETTINGS manager already owns the
selection, so the `pgrep` guard is belt-and-braces rather than load-bearing.

> `scripts/autostop.sh` does not need a matching stop: `xsettingsd` is in the
> session's process group and goes away with it. Confirm against
> `tests/test-autostop.sh` if that assumption is wrong for this session layout.

### 7.2 Dependencies

**Find** (`scripts/dwm-packages.sh:14`–`:15`):

```bash
	arch:x11)
		printf '%s\n' xorg-server xorg-xinit xorg-xrandr xorg-xset xorg-xsetroot xorg-xinput xorg-setxkbmap
		;;
```

**Replace with:**

```bash
	arch:x11)
		# xorg-xrdb: dwm-settings-display reads and writes Xft.dpi through it.
		#   It was already a hard requirement of the DPI actions and was simply
		#   missing from this list -- x11_resources_available() made it fail
		#   silently instead of loudly.
		# xsettingsd: the XSETTINGS manager that rescales already-running GTK
		#   and Qt clients on a DPI change. Every other DPI channel works
		#   without it.
		printf '%s\n' xorg-server xorg-xinit xorg-xrandr xorg-xrdb xorg-xset xorg-xsetroot xorg-xinput xorg-setxkbmap xsettingsd
		;;
```

**And in `archiso/packages.x86_64`, find:**

```
xorg-xrandr
xorg-xset
xorg-xsetroot
```

**Replace with:**

```
xorg-xrandr
xorg-xrdb
xorg-xset
xorg-xsetroot
xsettingsd
```

> `AGENTS.md` requires `archiso/packages.x86_64` to stay in sync with the shared
> dependency map, and `tests/test-arch-iso-builder.sh` checks it — run
> `make check-archiso` after this edit. Adding a dependency is also a platform
> change, so `SPEC.md` needs the `xsettingsd` line before this ships.

---

## 8. What this does and does not fix

**Live, no restart:**

- dwm border width and snap distance
- the Quickshell panel, popups, Control Center, launcher and Settings window
- every GTK 3/4 and Qt 5/6 xcb client that is already open — *only with
  `xsettingsd` installed and running*
- the X server's reported screen DPI, for clients that measure it

**Live for newly launched apps only:** anything reading `Xft.dpi` at start-up but
not watching XSETTINGS — terminals with their own font config, most Electron
builds, X clients using raw Xlib.

**Known gaps, stated rather than hidden:**

1. **`dpi-reset` leaves the server DPI where it was.** `xrandr --dpi` has no
   inverse. The resource and the XSETTINGS key are both cleared, so anything
   reading those is correct; only a client measuring the screen keeps the old
   value until the next session.
2. **Qt's `QT_SCALE_FACTOR` / device pixel ratio is start-up only.** Quickshell
   rescales through `Theme.uiScale`, which is real layout scaling, not Qt's DPR.
   Raster assets in the shell will resample rather than re-render at 2x. That is
   the correct trade for a live change; a crisp 2x needs a shell restart.
3. **Terminals with their own font size** (`config/alacritty/alacritty.toml`,
   `config/kitty/kitty.conf`) state points and are unaffected by `Xft.dpi`. Out
   of scope here; it belongs with the Appearance font work in
   `TASKS.md:APPEARANCE-001`.
4. **Without `xsettingsd`** the behaviour is exactly today's for already-running
   apps. The pane should say so — see §9.

---

## 9. Suggested Settings-pane copy

`DisplaySettingsPane.qml:24`–`:34` builds the DPI detail string. Worth extending
so the pane does not promise more than the session can deliver:

- when `xsettingsd` is running: *"Applies immediately to open windows."*
- when it is not: *"Applies to the desktop now, and to apps as you restart
  them."*

That needs a readiness bit in the `dpi` record from `emit_dpi()`. It is a
protocol change (a sixth field), so it is called out separately here rather than
folded into §3 — `SettingsModel.qml:216` guards on `fields.length >= 5`, so an
appended sixth field is backward compatible, but the protocol version should be
bumped alongside it.

---

## 10. Validation

Build and static checks:

```
make clean && make
make check-shell            # shellcheck over scripts/
make check-format
make check-display-setup
make check-display-profile
make check-archiso          # required by §7.2
scripts/quickshell-qmllint   # QML syntax for §5 and §6
```

Existing test to extend: `tests/test-settings.sh:333`-onward already stubs
`xrandr` and `xrdb` on a scratch `PATH` and asserts the `dpi-set` / `dpi-reset`
protocol. Add to it:

1. a stub `xsettingsd` and `pkill` on the same `PATH`, then assert
   `$DWM_XSETTINGS_CONFIG` contains `Xft/DPI 147456` after `dpi-set 144`;
2. assert an unrelated line already in that file survives the rewrite;
3. assert `$XDG_RUNTIME_DIR/dwm-settings-display/dpi.current` holds
   `dpi-state-protocol\t1` and `dpi\t144`;
4. assert `dpi-reset` removes the `Xft/DPI` line and republishes `96`;
5. assert `dpi-set` still succeeds with **no** `xsettingsd` on `PATH` — the
   degradation path is the one most likely to regress.

Live session, in order:

1. Log in at the default DPI. Confirm the panel, popups and borders are
   pixel-identical to before the change. **This is the regression that matters
   most** — `uiScale` is 1 and nothing should move.
2. Settings → Displays → set 144. Expect, without a logout: panel and popups
   grow; dwm borders thicken; already-open GTK and Qt apps rescale.
3. `xrdb -query | grep Xft.dpi` → `144`.
4. `dwm` stderr shows `dwm: display scale is now 144 dpi`.
5. Reset. Everything returns to the 96 DPI layout.
6. `pacman -Rdd xsettingsd`, repeat step 2: everything still works except
   already-running GTK/Qt apps. Nothing errors.
7. Set 384, then 72. Confirm the panel stays usable at both ends and that
   `Theme.uiScale` clamps at 3.0 rather than running away.
8. Two monitors at different scales: confirm the panel on each is sized from the
   one shared DPI. Per-monitor scaling is *not* part of this change.

---

## 11. Verification status of this proposal

What was actually run while writing this, against a scratch copy outside the
repo — the repository itself is untouched:

- **`dwm.c` §4.1–§4.8 compile clean.** All ten edits applied to a copy of
  `dwm.c`, then `gcc -std=c99 -pedantic -Wall` with the project's real
  pkg-config flags: zero errors, zero warnings. Baseline compiled the same way
  first, for comparison.
- **`scripts/dwm-settings-display` §3.1–§3.2 pass `bash -n` and `shellcheck -x`
  with no findings.**
- **The helper's behaviour was exercised** against stub `xrdb`, `xrandr`,
  `xsettingsd` and `pkill` on a scratch `PATH`, confirming:
  `dpi-set 144` writes `Xft/DPI 147456` while preserving an unrelated
  `Net/ThemeName` line; `dpi.current` contains the tab-separated record; the
  saved `Xft.dpi` and the merged resource are both correct; `dpi-reset` clears
  the XSETTINGS key and `Xft.dpi` while leaving `Xft.antialias` alone and
  republishes 96; `dpi-apply-saved` with nothing saved publishes 96 and exits 0;
  `dpi-set` succeeds unchanged with no `xsettingsd` on `PATH`; out-of-range
  values are still rejected.

What has **not** been tested and needs a live session:

- Anything in §5 and §6 — the QML was not run. `scripts/quickshell-qmllint` is
  the first gate.
- The panel-height handover in §5's callout: whether dwm picks up the resized
  Quickshell panel through `updatealtbar()`.
- Whether `xrandr --dpi` is honoured on this hardware and driver.
- Whether GTK and Qt clients actually rescale in place via `xsettingsd` here.
- Every §7 packaging change.
