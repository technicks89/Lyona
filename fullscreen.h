/* See LICENSE file for copyright and license details.
 *
 * A client's fullscreen mode (#533): one value and one table of moves, with
 * no X in them, so tests/test-fullscreen-state.c checks every pair. dwm.c's
 * setfullscreenmode() is the only place a client's mode changes; this file
 * only says which mode an event leads to and what each mode means. Before
 * #533 the mode was spread over isfullscreen, fakefullscreen (0-3) and
 * iswindowedfullscreen, and nothing said which combinations were legal.
 */
#ifndef LYONA_FULLSCREEN_H
#define LYONA_FULLSCREEN_H

enum {
	FsNone,         /* a normal window (zero, so a new client starts here) */
	FsReal,         /* EWMH fullscreen, covering its monitor */
	FsFake,         /* told it is fullscreen, kept in its tile: Super+Shift+Y */
	FsFakeArmed,    /* fake mode on, not fullscreen: its next request is fake */
	FsRealOverFake, /* real fullscreen a rule gave while fake mode was on;
	                 * the client leaving it goes back to fake mode */
	FsWindowed,     /* a rule's borderless windowed fullscreen (#477): covers
	                 * the monitor without EWMH fullscreen and ignores the
	                 * client's own requests */
	FsModeLast
};

enum {
	FsEvClientOn,     /* _NET_WM_STATE asked, or present when it maps */
	FsEvClientOff,
	FsEvUserFake,     /* togglefakefullscreen (Super+Shift+Y) */
	FsEvRuleReal,     /* a rule's fullscreen=1, at map or a late title */
	FsEvRuleWindowed, /* a rule's fakefullscreen=1 */
	FsEvLast
};

/* The client thinks of itself as fullscreen, or covers its monitor. */
static inline int
fs_active(int mode)
{
	return mode == FsReal || mode == FsFake || mode == FsRealOverFake
		|| mode == FsWindowed;
}

/* Covers its monitor: borderless, floating, its tile geometry kept to go
 * back to, and nothing else on the monitor raised over it. */
static inline int
fs_covers(int mode)
{
	return mode == FsReal || mode == FsRealOverFake || mode == FsWindowed;
}

/* What _NET_WM_STATE_FULLSCREEN says. */
static inline int
fs_ewmh(int mode)
{
	return mode == FsReal || mode == FsFake || mode == FsRealOverFake;
}

static inline int
fs_windowed(int mode)
{
	return mode == FsWindowed;
}

/* The mode EVENT leads to from MODE, or -1 for a mode or event that does not
 * exist. Every pair is a legal move; staying put is one too. */
static inline int
fs_step(int mode, int event)
{
	static const unsigned char next[FsModeLast][FsEvLast] = {
		/*                ClientOn        ClientOff    UserFake  RuleReal        RuleWindowed */
		[FsNone]         = { FsReal,         FsNone,      FsFake,   FsReal,         FsWindowed },
		[FsReal]         = { FsReal,         FsNone,      FsFake,   FsReal,         FsWindowed },
		[FsFake]         = { FsFake,         FsFakeArmed, FsNone,   FsRealOverFake, FsWindowed },
		[FsFakeArmed]    = { FsFake,         FsFakeArmed, FsNone,   FsRealOverFake, FsWindowed },
		/* Asked again while already fullscreen: nothing changes. */
		[FsRealOverFake] = { FsRealOverFake, FsFakeArmed, FsFake,   FsRealOverFake, FsWindowed },
		/* The client's own requests are ignored; its property is put back. */
		[FsWindowed]     = { FsWindowed,     FsWindowed,  FsNone,   FsReal,         FsWindowed },
	};

	if (mode < 0 || mode >= FsModeLast || event < 0 || event >= FsEvLast)
		return -1;
	return next[mode][event];
}

#endif
