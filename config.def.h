/* See LICENSE file for copyright and license details. */

static const unsigned int refresh_rate = 60;
static const unsigned int enable_noborder = 1;
static const int cursorwarp         = 1;
static const unsigned int snap      = 32;
static const int swallowfloating    = 0;

static const int showbar            = 1;
static const int topbar             = 1;
#define ICONSIZE                      17
#define ICONSPACING                   5
#define SHOWWINICON                   1

// static const char dmenufont[]       = "MesloLGS Nerd Font Mono:size=12";

static const char *fonts[]          = { "MesloLGS Nerd Font Mono:size=12:antialias=true:autohint=true", "NotoColorEmoji:pixelsize=14:antialias=true:autohint=true" };

static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

// static const char ptagf[] = "[%s %s]";
// static const char etagf[] = "[%s]";
// static const int lcaselbl = 0;

static const float mfact     = 0.55;
static const int nmaster     = 1;
static const int resizehints = 1;
static const int lockfullscreen = 1;

static const Layout layouts[] = {

	{ "[]=",      tile },
	{ "><>",      NULL },
	{ "[M]",      monocle },
};

#define MODKEY Mod4Mask
#define STATUSBAR "dwmblocks"
