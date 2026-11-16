/* #533: every (mode, event) pair of fullscreen.h, against the logic dwm.c
 * had before it (setfullscreen, clientmessage, togglefakefullscreen and
 * applyfullscreenrule as of f3f836d, without X): the mode reached, whether
 * the geometry is kept or restored, and what _NET_WM_STATE_FULLSCREEN ends
 * up saying. Where #533 changed a move on purpose, the pair is listed in
 * `changed` with the reason, and it must differ from the old logic. */
#include <stdio.h>
#include <string.h>

#include "../fullscreen.h"

/* ── The old logic: isfullscreen (I), fakefullscreen (F, 0-3), and
 * iswindowedfullscreen (W), with the saved-geometry bit and the property. */
typedef struct { int I, F, W, saved, ewmh; } Old;
enum { GeomKeep, GeomSave, GeomRestore };
static int old_geom;

static void
old_ewmh(Old *c, int fs)
{
	c->ewmh = fs && !c->W;
}

static void
old_setfullscreen(Old *c, int fullscreen)
{
	int savestate = 0, restorestate = 0;

	if (c->W && !fullscreen)
		c->F = 0;
	if ((c->F == 0 && fullscreen && !c->I) || (c->F == 2 && fullscreen))
		savestate = 1;
	else if ((c->F == 0 && !fullscreen && c->I) || (c->F >= 2 && !fullscreen))
		restorestate = 1;
	if (c->F == 2 && !fullscreen && c->I) {
		c->F = 1;
		c->I = 1;
		fullscreen = 1;
	} else if (c->F == 3)
		c->F = 1;
	if (fullscreen != c->I || c->W)
		old_ewmh(c, fullscreen);
	c->I = fullscreen;
	if (!fullscreen)
		c->W = 0;
	if (savestate && !c->saved) {
		c->saved = 1;
		old_geom = GeomSave;
	} else if (restorestate && c->saved) {
		c->saved = 0;
		old_geom = GeomRestore;
	}
}

static void
old_event(Old *c, int event)
{
	old_geom = GeomKeep;
	switch (event) {
	case FsEvClientOn:
	case FsEvClientOff:
		if (c->W) {
			old_ewmh(c, 0);
			break;
		}
		if (c->F == 2 && c->I)
			c->F = 3;
		old_setfullscreen(c, event == FsEvClientOn);
		break;
	case FsEvUserFake:
		if (c->W)
			old_setfullscreen(c, 0);
		else if (c->F != 1 && c->I) {
			c->F = 2;
			old_setfullscreen(c, 0);
		} else if (c->F == 1) {
			old_setfullscreen(c, 0);
			c->F = 0;
		} else {
			c->F = 1;
			old_setfullscreen(c, 1);
		}
		break;
	case FsEvRuleReal:
	case FsEvRuleWindowed:
		c->W = event == FsEvRuleWindowed;
		old_ewmh(c, !c->W);
		if (c->F == 1)
			c->F = 2;
		old_setfullscreen(c, 1);
		break;
	}
}

/* Each mode as the old fields held it; windowed came as F 0 or F 2, which
 * differed only in focusstack(), so F 2 is read as windowed too. */
static Old
old_of(int mode)
{
	static const int fields[FsModeLast][3] = {
		[FsNone] = { 0, 0, 0 },         [FsReal] = { 1, 0, 0 },
		[FsFake] = { 1, 1, 0 },         [FsFakeArmed] = { 0, 1, 0 },
		[FsRealOverFake] = { 1, 2, 0 }, [FsWindowed] = { 1, 0, 1 },
	};
	Old c = { fields[mode][0], fields[mode][1], fields[mode][2], 0, 0 };

	c.saved = fs_covers(mode);
	c.ewmh = fs_ewmh(mode);
	return c;
}

static int
mode_of(Old c)
{
	if (c.W)
		return c.I ? FsWindowed : -1;
	if (!c.I)
		return c.F == 0 ? FsNone : c.F == 1 ? FsFakeArmed : -1;
	return c.F == 0 ? FsReal : c.F == 1 ? FsFake : c.F == 2 ? FsRealOverFake : -1;
}

/* ── What dwm.c's setfullscreenmode() does with a move. */
static int
geom_of(int from, int to)
{
	if (!fs_covers(from) && fs_covers(to))
		return GeomSave;
	if (fs_covers(from) && !fs_covers(to))
		return GeomRestore;
	return GeomKeep;
}

static const char *mode_names[] = { "None", "Real", "Fake", "FakeArmed", "RealOverFake", "Windowed" };
static const char *event_names[] = { "ClientOn", "ClientOff", "UserFake", "RuleReal", "RuleWindowed" };

/* The moves #533 changed on purpose, and where each now leads. */
static const struct { int mode, event, to; const char *why; } changed[] = {
	/* (b): asked again while fullscreen, the old logic dropped to fake but
	 * kept the monitor's size and a saved geometry, so a later fullscreen
	 * did not cover the monitor. */
	{ FsRealOverFake, FsEvClientOn, FsRealOverFake, "a repeated request no longer drops to fake" },
};

/* The listed move's new target, or -1 when the move is not listed. */
static int
changed_to(int mode, int event)
{
	size_t i;

	for (i = 0; i < sizeof changed / sizeof changed[0]; i++)
		if (changed[i].mode == mode && changed[i].event == event)
			return changed[i].to;
	return -1;
}

int
main(void)
{
	int mode, event, failures = 0, pairs = 0;

	for (mode = 0; mode < FsModeLast; mode++)
		for (event = 0; event < FsEvLast; event++) {
			Old old = old_of(mode);
			int to = fs_step(mode, event), old_to, same;

			pairs++;
			old_event(&old, event);
			old_to = mode_of(old);
			same = old_to == to && old_geom == geom_of(mode, to)
				&& old.ewmh == fs_ewmh(to) && old.saved == fs_covers(to);
			if (to < 0 || to >= FsModeLast) {
				printf("FAIL %s + %s: no mode (%d)\n", mode_names[mode], event_names[event], to);
				failures++;
			} else if (changed_to(mode, event) >= 0 && to != changed_to(mode, event)) {
				printf("FAIL %s + %s: %s, but #533 made it %s\n", mode_names[mode],
					event_names[event], mode_names[to], mode_names[changed_to(mode, event)]);
				failures++;
			} else if (!same && changed_to(mode, event) < 0) {
				printf("FAIL %s + %s: %s, geometry %d, ewmh %d; the old logic: %s, geometry %d, ewmh %d, saved %d\n",
					mode_names[mode], event_names[event], mode_names[to],
					geom_of(mode, to), fs_ewmh(to), old_to >= 0 ? mode_names[old_to] : "?",
					old_geom, old.ewmh, old.saved);
				failures++;
			} else if (same && changed_to(mode, event) >= 0) {
				printf("FAIL %s + %s: listed as changed, but it matches the old logic\n",
					mode_names[mode], event_names[event]);
				failures++;
			}
		}

	/* What the modes mean. */
	for (mode = 0; mode < FsModeLast; mode++) {
		if (fs_covers(mode) && !fs_active(mode)) {
			printf("FAIL %s covers the monitor but is not active\n", mode_names[mode]);
			failures++;
		}
		if (fs_ewmh(mode) && !fs_active(mode)) {
			printf("FAIL %s says fullscreen but is not active\n", mode_names[mode]);
			failures++;
		}
	}
	if (FsNone != 0 || fs_active(FsNone)) {
		printf("FAIL a new client (zeroed) is not a normal window\n");
		failures++;
	}
	if (fs_step(-1, FsEvClientOn) != -1 || fs_step(FsModeLast, FsEvClientOn) != -1
			|| fs_step(FsNone, -1) != -1 || fs_step(FsNone, FsEvLast) != -1) {
		printf("FAIL a mode or event that does not exist was accepted\n");
		failures++;
	}

	if (failures) {
		printf("fullscreen state (#533): %d of %d pairs or checks failed\n", failures, pairs);
		return 1;
	}
	printf("fullscreen state (#533): PASS (%d pairs)\n", pairs);
	return 0;
}
