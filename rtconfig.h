/* See LICENSE file for copyright and license details.
 *
 * The runtime configuration (config.c): hotkeys.toml, themes.toml and
 * window-rules.toml under ${XDG_CONFIG_HOME:-$HOME/.config}/lyona, with the
 * shipped defaults as the fallback, watched with inotify (Linux) for hot
 * reload. The file is named for what it holds; config.h is the compile-time
 * configuration copied from config.def.h.
 *
 * dwm.c owns the X state. config.c reads the files and hands back keys,
 * buttons, rules and a theme; it never touches a window, a monitor or the
 * colour schemes. Requires <X11/Xlib.h> and <stddef.h> first.
 */

enum { ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle,
       ClkClientWin, ClkRootWin, ClkLast };

typedef union {
	int i;
	unsigned int ui;
	float f;
	const void *v;
} Arg;

typedef struct {
	unsigned int click;
	unsigned int mask;
	unsigned int button;
	void (*func)(const Arg *arg);
	const Arg arg;
} Button;

typedef struct {
	unsigned int mod;
	KeySym keysym;
	void (*func)(const Arg *);
	const Arg arg;
} Key;

typedef struct Monitor Monitor;
typedef struct {
	const char *symbol;
	void (*arrange)(Monitor *);
} Layout;

typedef struct {
	const char *class;
	const char *instance;
	const char *title;
	unsigned int tags;
	int isfloating;
	int alwaysontop;
	int isterminal;
	int noswallow;
	int monitor;
} Rule;

/* A function a binding may name in hotkeys.toml. */
typedef struct {
	const char *name;
	void (*func)(const Arg *);
} ConfigFunc;

/* What the bindings refer to: dwm's functions, and the facts from config.h. */
typedef struct {
	const ConfigFunc *funcs;
	size_t nfuncs;
	const Layout *layouts;
	size_t nlayouts;
	unsigned int ntags;
	unsigned int modkey;
	/* The keys used when no hotkeys.toml loads: a terminal and quit. */
	const Key *emergencykeys;
	size_t nemergencykeys;
} ConfigEnv;

/* themes.toml's active theme, for dwm.c to apply. */
typedef struct {
	char colors[2][3][8];   /* [SchemeNorm, SchemeSel][fg, bg, border] */
	long borderpx;          /* at 96 dpi; -1 when themes.toml does not set it */
} ConfigTheme;

/* What runtime_config_poll found. */
#define CONFIG_RELOAD 1     /* a config file changed */
#define CONFIG_THEMES 2     /* themes.toml among them */

/* The bindings and rules in use; empty until the first runtime_config_load. */
extern const Key    *rt_keys;
extern int           rt_nkeys;
extern const Button *rt_buttons;
extern int           rt_nbuttons;
extern const Rule   *rt_rules;
extern int           rt_nrules;

/* Finds the user and default config directories, normalizes XDG_CONFIG_HOME
 * and XDG_DATA_HOME in the environment, and starts the inotify watches. */
void runtime_config_setup(const ConfigEnv *env);
/* Loads all three files. Returns 1 and fills *theme when themes.toml loaded. */
int runtime_config_load(ConfigTheme *theme);
/* The inotify descriptor for select(), or -1. */
int runtime_config_fd(void);
/* Reads the pending inotify events: CONFIG_RELOAD and CONFIG_THEMES, or 0. */
int runtime_config_poll(void);
/* Async-signal-safe: asks for a reload (SIGUSR1). */
void runtime_config_mark_reload_pending(void);
/* Returns 1 once after runtime_config_mark_reload_pending. */
int runtime_config_take_pending(void);
