/* See LICENSE file for copyright and license details.
 *
 * The runtime configuration: loads hotkeys.toml, themes.toml and
 * window-rules.toml, falls back to the shipped defaults, and watches both
 * directories with inotify (Linux) for hot reload. The interface is
 * rtconfig.h. Nothing here blocks: the files are read when dwm.c asks, after
 * select() says the watch has events.
 */
#include <ctype.h>
#include <limits.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <X11/Xlib.h>

#include "rtconfig.h"
#include "tomlparser.h"
#include "util.h"

const Key    *rt_keys  = NULL;
int           rt_nkeys = 0;
const Button *rt_buttons  = NULL;
int           rt_nbuttons = 0;
const Rule   *rt_rules  = NULL;
int           rt_nrules = 0;

static const ConfigEnv *env;
/* dwm's spawn, found by name in env at setup. */
static void (*spawnfunc)(const Arg *);

#define TOML_RULES_MAX 64
static Rule          rt_rules_buf[TOML_RULES_MAX];
static char          rt_rules_strbuf[TOML_RULES_MAX * 3][TOML_MAX_STR];

static int           inotify_fd = -1;
static int           inotify_wd = -1;
static int           inotify_wd3 = -1;
/* The config home (~/.config) itself, so that a lyona directory created or
 * recreated after login is watched too (Sync Sprint 16 R16-09). */
static int           inotify_wd_parent = -1;
#define USER_CONFIG_WATCH (IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVE_SELF)
static char          toml_config_dir[PATH_MAX];
static char          toml_hotkeys_path[PATH_MAX];
static char          toml_themes_path[PATH_MAX];
static char          toml_rules_path[PATH_MAX];

static volatile sig_atomic_t sig_reload_pending = 0;

#define TOML_ARENA_CAP 65536u
static char   toml_arena_buf[TOML_ARENA_CAP];
static size_t toml_arena_pos = 0;

static char          dwm_config_home_dir[PATH_MAX];
static char          dwm_data_home_dir[PATH_MAX];
static char          toml_default_dir[PATH_MAX];
static char          toml_hotkeys_default_path[PATH_MAX];
static char          toml_themes_default_path[PATH_MAX];
static char          toml_rules_default_path[PATH_MAX];

#define TOML_BUTTONS_MAX 32
static Button        rt_buttons_buf[TOML_BUTTONS_MAX];

static void runtime_config_ensure_user_watch(void);
static void setup_inotify(void);

/* The shipped default TOMLs (Sync Sprint 12 S12-13): PREFIX/share/lyona/config
 * beside an installed PREFIX/bin/dwm, else the config/ of a checkout running
 * ./dwm in place. Found from the executable at run time rather than compiled
 * in, because install.sh builds and installs with different DATADIR values. */
static int
default_config_dir(char *out, size_t size)
{
	char dir[PATH_MAX], *slash;
	struct stat st;

	if (!exe_dir(dir, sizeof(dir)))
		return 0;
	if ((slash = strrchr(dir, '/'))) {
		*slash = '\0';           /* PREFIX */
		if (pathjoin(out, size, dir, "share/lyona/config")
		    && stat(out, &st) == 0 && S_ISDIR(st.st_mode))
			return 1;
		*slash = '/';
	}
	return pathjoin(out, size, dir, "config");
}

static void *
toml_alloc(size_t sz)
{
	sz = (sz + 7u) & ~7u;
	if (toml_arena_pos + sz > TOML_ARENA_CAP)
		return NULL;
	void *p = toml_arena_buf + toml_arena_pos;
	toml_arena_pos += sz;
	return p;
}

static unsigned int
parse_single_mod(const char *s)
{
	if (strcmp(s, "MODKEY")      == 0 || strcmp(s, "SUPER")   == 0) return env->modkey;
	if (strcmp(s, "ShiftMask")   == 0 || strcmp(s, "SHIFT")   == 0) return ShiftMask;
	if (strcmp(s, "ControlMask") == 0 || strcmp(s, "CTRL")    == 0) return ControlMask;
	if (strcmp(s, "Mod1Mask")    == 0 || strcmp(s, "ALT")     == 0) return Mod1Mask;
	if (strcmp(s, "Mod2Mask")    == 0) return Mod2Mask;
	if (strcmp(s, "Mod3Mask")    == 0) return Mod3Mask;
	if (strcmp(s, "Mod4Mask")    == 0) return Mod4Mask;
	if (strcmp(s, "Mod5Mask")    == 0) return Mod5Mask;
	return 0;
}

static unsigned int
parse_mod_mask(const TomlValue *v)
{
	if (!v) return 0;

	if (v->type == TOML_STRING) {
		unsigned int mask = 0;
		const char *p = v->s;
		char tok[32];
		while (*p) {
			while (isspace((unsigned char)*p)) p++;
			if (!*p) break;
			int ti = 0;
			while (*p && !isspace((unsigned char)*p) && ti < 31)
				tok[ti++] = *p++;
			tok[ti] = '\0';
			mask |= parse_single_mod(tok);
		}
		return mask;
	}

	if (v->type == TOML_ARRAY) {
		unsigned int mask = 0;
		int i;
		for (i = 0; i < v->a.len; i++)
			mask |= parse_single_mod(v->a.items[i]);
		return mask;
	}
	return 0;
}

static void (*lookup_func(const char *name))(const Arg *)
{
	size_t i;

	for (i = 0; i < env->nfuncs; i++)
		if (strcmp(name, env->funcs[i].name) == 0)
			return env->funcs[i].func;
	return NULL;
}

static void
notify_bad_config(const char *filename, const char *reason)
{
	const char *base = strrchr(filename, '/');
	base = base ? base + 1 : filename;
	char msg[768];
	int len = snprintf(msg, sizeof(msg), "%s: %s", base, reason);
	if (len < 0)
		return;
	if ((size_t)len >= sizeof(msg))
		copystr(msg, sizeof(msg), reason);
	pid_t pid = fork();
	if (pid == 0) {
		execlp("notify-send", "notify-send", "-u", "critical",
		       "dwm: bad config", msg, (char *)NULL);
		_exit(127);
	}
}

static unsigned int
lookup_click(const char *name)
{
	if (strcmp(name, "ClkTagBar")    == 0) return ClkTagBar;
	if (strcmp(name, "ClkLtSymbol")  == 0) return ClkLtSymbol;
	if (strcmp(name, "ClkStatusText")== 0) return ClkStatusText;
	if (strcmp(name, "ClkWinTitle")  == 0) return ClkWinTitle;
	if (strcmp(name, "ClkClientWin") == 0) return ClkClientWin;
	if (strcmp(name, "ClkRootWin")   == 0) return ClkRootWin;
	return ClkLast;
}

static void
expand_var_to(const char *src, const TomlDoc *doc, char *dst, size_t dstsz)
{
	if (!strchr(src, '$')) {
		copystr(dst, dstsz, src);
		return;
	}
	const char *p = src;
	size_t di = 0;
	while (*p && di < dstsz - 1) {
		if (*p == '$') {
			const char *ns = p + 1;
			const char *ne = ns;
			while (isalnum((unsigned char)*ne) || *ne == '_') ne++;
			int nlen = (int)(ne - ns);
			if (nlen > 0 && nlen < TOML_MAX_STR) {
				char vname[TOML_MAX_STR];
				strncpy(vname, ns, (size_t)nlen);
				vname[nlen] = '\0';
				const TomlValue *tv = toml_get(doc, "vars", vname);
				if (tv && tv->type == TOML_STRING) {
					size_t vl = strlen(tv->s);
					if (di + vl < dstsz - 1) {
						memcpy(dst + di, tv->s, vl);
						di += vl;
					}
					p = ne;
					continue;
				}
			}
		}
		dst[di++] = *p++;
	}
	dst[di] = '\0';
}

/* Whether a spawn binding has something to run: the same exec-or-cmd test
 * build_spawn_arg applies, without allocating, so hotkeys_doc_usable can tell
 * before the key arena is reused. */
static int
spawn_has_command(const TomlDoc *doc, const char *section, int tidx)
{
	const TomlValue *vexec = toml_table_get(doc, section, tidx, "exec");
	const TomlValue *vcmd  = toml_table_get(doc, section, tidx, "cmd");

	return (vexec && vexec->type == TOML_ARRAY && vexec->a.len > 0)
	       || (vcmd && vcmd->type == TOML_STRING);
}

static Arg
build_spawn_arg(const TomlDoc *doc, const char *section, int tidx)
{
	Arg arg = {0};
	const TomlValue *vexec = toml_table_get(doc, section, tidx, "exec");
	const TomlValue *vcmd  = toml_table_get(doc, section, tidx, "cmd");
	if (vexec && vexec->type == TOML_ARRAY && vexec->a.len > 0) {
		int argc = vexec->a.len;
		const char **argv = toml_alloc((argc + 1) * sizeof(char *));
		if (!argv) return arg;
		for (int j = 0; j < argc; j++) {
			char expanded[TOML_MAX_STR];
			expand_var_to(vexec->a.items[j], doc, expanded, TOML_MAX_STR);
			size_t slen = strlen(expanded) + 1;
			char *s = toml_alloc(slen);
			if (!s) return arg;
			memcpy(s, expanded, slen);
			argv[j] = s;
		}
		argv[argc] = NULL;
		arg.v = argv;
	} else if (vcmd && vcmd->type == TOML_STRING) {
		const char **argv = toml_alloc(4 * sizeof(char *));
		if (!argv) return arg;
		char expanded[TOML_MAX_STR];
		expand_var_to(vcmd->s, doc, expanded, TOML_MAX_STR);
		size_t slen = strlen(expanded) + 1;
		char *cmd = toml_alloc(slen);
		if (!cmd) return arg;
		memcpy(cmd, expanded, slen);
		argv[0] = "/bin/sh";
		argv[1] = "-c";
		argv[2] = cmd;
		argv[3] = NULL;
		arg.v = argv;
	}
	return arg;
}

static Arg
build_arg(const char *func_name, const TomlDoc *doc,
          const char *section, int tidx)
{
	Arg arg = {0};
	const TomlValue *v;
	if (strcmp(func_name, "spawn") == 0)
		return build_spawn_arg(doc, section, tidx);
	if (strcmp(func_name, "setlayout") == 0) {
		v = toml_table_get(doc, section, tidx, "layout_idx");
		int idx = (v && v->type == TOML_INT) ? (int)v->i : 0;
		if (idx < 0 || (size_t)idx >= env->nlayouts) idx = 0;
		arg.v = &env->layouts[idx];
		return arg;
	}
	v = toml_table_get(doc, section, tidx, "i");
	if (v) {
		if (v->type == TOML_INT)   { arg.i = (int)v->i;   return arg; }
		if (v->type == TOML_FLOAT) { arg.i = (int)v->d;   return arg; }
	}
	v = toml_table_get(doc, section, tidx, "ui");
	if (v && v->type == TOML_INT) { arg.ui = (unsigned int)v->i; return arg; }
	v = toml_table_get(doc, section, tidx, "f");
	if (v) {
		if (v->type == TOML_FLOAT) { arg.f = (float)v->d; return arg; }
		if (v->type == TOML_INT)   { arg.f = (float)v->i; return arg; }
	}
	return arg;
}

/* Whether a parsed document holds anything worth loading. NULL: any entry. */
typedef int (*TomlUsable)(const TomlDoc *doc);

static int
toml_doc_ok(const char *path, TomlDoc *doc, TomlUsable usable)
{
	if (!path || !path[0] || !toml_parse(path, doc))
		return 0;
	/* The parser keeps the first TOML_MAX_ENTRIES and drops the rest; say so,
	 * or themes at the end of a long file vanish without a word (S12-14). */
	if (doc->truncated)
		fprintf(stderr, "dwm: %s has more than %d entries; the rest were ignored\n",
		        path, TOML_MAX_ENTRIES);
	if (doc->long_lines)
		fprintf(stderr, "dwm: %s has %d line(s) longer than %d bytes; they were ignored\n",
		        path, doc->long_lines, TOML_MAX_LINE - 1);
	return doc->n > 0 && (!usable || usable(doc));
}

/* Load the user's file, or else the shipped default (Sync Sprint 12 S12-04).
 * A user file that does not load is reported. On a live reload (have_previous)
 * the config already in use is kept, so a half-saved edit never takes the keys
 * away; at startup the shipped default is loaded instead of nothing. Returns 1
 * when doc holds a config to apply. */
static int
toml_load_with_fallback(TomlDoc *doc, const char *user_path,
                        const char *default_path, const char *what,
                        TomlUsable usable, int have_previous)
{
	int user_exists = user_path && user_path[0] && access(user_path, F_OK) == 0;

	if (user_exists) {
		if (toml_doc_ok(user_path, doc, usable))
			return 1;
		if (have_previous) {
			notify_bad_config(user_path, "invalid config - kept the previous config");
			return 0;
		}
	}
	if (toml_doc_ok(default_path, doc, usable)) {
		if (user_exists)
			notify_bad_config(user_path, "invalid config - loaded defaults");
		return 1;
	}
	if (user_exists)
		notify_bad_config(user_path, "invalid config - and the default did not load");
	fprintf(stderr, "dwm: cannot load %s (no usable user or default config)\n", what);
	return 0;
}

/* A hotkeys document is usable when at least one binding in it could be
 * grabbed: a known key and function, or a tag key for a tag that exists. */
static int
hotkeys_doc_usable(const TomlDoc *doc)
{
	int i, n;

	n = toml_table_count(doc, "keys");
	for (i = 0; i < n; i++) {
		const TomlValue *vkey  = toml_table_get(doc, "keys", i, "key");
		const TomlValue *vfunc = toml_table_get(doc, "keys", i, "func");
		void (*fn)(const Arg *);
		if (!vkey || vkey->type != TOML_STRING || !vfunc || vfunc->type != TOML_STRING
		    || XStringToKeysym(vkey->s) == NoSymbol || !(fn = lookup_func(vfunc->s)))
			continue;
		/* The loader refuses a spawn with nothing to run. */
		if (fn == spawnfunc && !spawn_has_command(doc, "keys", i))
			continue;
		return 1;
	}
	n = toml_table_count(doc, "tag_keys");
	for (i = 0; i < n; i++) {
		const TomlValue *vkey = toml_table_get(doc, "tag_keys", i, "key");
		const TomlValue *vtag = toml_table_get(doc, "tag_keys", i, "tag");
		if (vkey && vkey->type == TOML_STRING && vtag && vtag->type == TOML_INT
		    && vtag->i >= 0 && vtag->i < (long)env->ntags
		    && XStringToKeysym(vkey->s) != NoSymbol)
			return 1;
	}
	return 0;
}

static void
use_emergency_keys(const char *user_path)
{
	rt_keys  = env->emergencykeys;
	rt_nkeys = (int)env->nemergencykeys;
	fprintf(stderr, "dwm: no usable hotkeys; only Super+x (terminal) and Super+Shift+q (quit)\n");
	notify_bad_config(user_path && user_path[0] ? user_path : "hotkeys.toml",
	                  "no usable hotkeys - only Super+x (terminal) and Super+Shift+q (quit) work");
}

static void
load_hotkeys_toml(const char *user_path, const char *default_path)
{
	static TomlDoc doc;
	static int from_config;

	if (!toml_load_with_fallback(&doc, user_path, default_path, "hotkeys",
	                             hotkeys_doc_usable, from_config)) {
		if (!from_config)
			use_emergency_keys(user_path);
		return;
	}
	int nregular = toml_table_count(&doc, "keys");
	int ntag     = toml_table_count(&doc, "tag_keys");
	int total    = nregular + ntag * 4;
	if (total <= 0) return;

	toml_arena_pos = 0;
	Key *newkeys = toml_alloc((size_t)total * sizeof(Key));
	if (!newkeys) {
		fprintf(stderr, "dwm: TOML arena overflow\n");
		return;
	}
	int nk = 0;

	for (int i = 0; i < nregular; i++) {
		const TomlValue *vkey  = toml_table_get(&doc, "keys", i, "key");
		const TomlValue *vmod  = toml_table_get(&doc, "keys", i, "mod");
		const TomlValue *vfunc = toml_table_get(&doc, "keys", i, "func");
		if (!vkey || vkey->type != TOML_STRING) continue;
		if (!vfunc || vfunc->type != TOML_STRING) continue;
		KeySym ks = XStringToKeysym(vkey->s);
		if (ks == NoSymbol) {
			fprintf(stderr, "dwm: unknown keysym '%s'\n", vkey->s);
			continue;
		}
		void (*fn)(const Arg *) = lookup_func(vfunc->s);
		if (!fn) {
			fprintf(stderr, "dwm: unknown func '%s'\n", vfunc->s);
			continue;
		}
		if (nk >= total) break;
		Arg tmp_arg = build_arg(vfunc->s, &doc, "keys", i);
		if (fn == spawnfunc && !tmp_arg.v) {
			fprintf(stderr, "dwm: no spawn arguments for '%s'\n", vkey->s);
			continue;
		}
		newkeys[nk].mod    = parse_mod_mask(vmod);
		newkeys[nk].keysym = ks;
		newkeys[nk].func   = fn;
		memcpy((void *)&newkeys[nk].arg, &tmp_arg, sizeof(Arg));
		nk++;
	}

	static const char *tag_funcs[4] = {
		"view", "toggleview", "tag", "toggletag"
	};
	static const unsigned int tag_mod_extra[4] = {
		0, ControlMask, ShiftMask, ControlMask|ShiftMask
	};
	for (int i = 0; i < ntag; i++) {
		const TomlValue *vkey = toml_table_get(&doc, "tag_keys", i, "key");
		const TomlValue *vtag = toml_table_get(&doc, "tag_keys", i, "tag");
		if (!vkey || vkey->type != TOML_STRING) continue;
		if (!vtag || vtag->type != TOML_INT) continue;
		if (vtag->i < 0 || vtag->i >= (long)env->ntags) {
			fprintf(stderr, "dwm: tag_keys tag %ld is not a tag (0-%d)\n",
			        vtag->i, (int)env->ntags - 1);
			continue;
		}
		KeySym ks = XStringToKeysym(vkey->s);
		if (ks == NoSymbol) continue;
		unsigned int tag_bit = 1u << vtag->i;
		for (int j = 0; j < 4 && nk < total; j++) {
			Arg tmp_arg;
			tmp_arg.ui = tag_bit;
			newkeys[nk].mod    = env->modkey | tag_mod_extra[j];
			newkeys[nk].keysym = ks;
			newkeys[nk].func   = lookup_func(tag_funcs[j]);
			memcpy((void *)&newkeys[nk].arg, &tmp_arg, sizeof(Arg));
			nk++;
		}
	}

	if (nk == 0) {
		/* Every binding was refused (for example spawns with nothing to run).
		 * The arena was reused, so the previous keys are gone too. */
		from_config = 0;
		use_emergency_keys(user_path);
		return;
	}
	rt_keys  = newkeys;
	rt_nkeys = nk;
	from_config = 1;

	{
		int nbtn = toml_table_count(&doc, "buttons");
		if (nbtn > TOML_BUTTONS_MAX) nbtn = TOML_BUTTONS_MAX;
		int nb = 0;
		for (int i = 0; i < nbtn; i++) {
			const TomlValue *vclick = toml_table_get(&doc, "buttons", i, "click");
			const TomlValue *vmod   = toml_table_get(&doc, "buttons", i, "mod");
			const TomlValue *vbtn   = toml_table_get(&doc, "buttons", i, "button");
			const TomlValue *vfunc  = toml_table_get(&doc, "buttons", i, "func");
			if (!vclick || vclick->type != TOML_STRING) continue;
			if (!vfunc  || vfunc->type  != TOML_STRING) continue;
			if (!vbtn   || vbtn->type   != TOML_INT)    continue;
			unsigned int click = lookup_click(vclick->s);
			if (click == ClkLast) {
				fprintf(stderr, "dwm: unknown click '%s'\n", vclick->s);
				continue;
			}
			void (*fn)(const Arg *) = lookup_func(vfunc->s);
			if (!fn) {
				fprintf(stderr, "dwm: unknown func '%s'\n", vfunc->s);
				continue;
			}
			if (nb >= TOML_BUTTONS_MAX) break;
			Arg tmp_arg = build_arg(vfunc->s, &doc, "buttons", i);
			if (fn == spawnfunc && !tmp_arg.v) {
				fprintf(stderr, "dwm: no spawn arguments for click '%s'\n", vclick->s);
				continue;
			}
			Button *b = &rt_buttons_buf[nb];
			b->click  = click;
			b->mask   = parse_mod_mask(vmod);
			b->button = (unsigned int)vbtn->i;
			b->func   = fn;
			memcpy((void *)&b->arg, &tmp_arg, sizeof(Arg));
			nb++;
		}
		rt_buttons  = nb > 0 ? rt_buttons_buf : NULL;
		rt_nbuttons = nb;
		fprintf(stderr, "dwm: loaded %d button bindings from hotkeys config\n", nb);
	}
	fprintf(stderr, "dwm: loaded %d keybinds from hotkeys config\n", nk);
}

/* Returns 1 and fills *theme when themes.toml (or its default) loaded. */
static int
load_themes_toml(const char *user_path, const char *default_path, ConfigTheme *theme)
{
	static TomlDoc doc;
	static int from_config;

	if (!toml_load_with_fallback(&doc, user_path, default_path, "themes", NULL, from_config))
		return 0;
	from_config = 1;

	char *c_normfg = theme->colors[0][0], *c_normbg = theme->colors[0][1];
	char *c_normborder = theme->colors[0][2];
	char *c_selfg = theme->colors[1][0], *c_selbg = theme->colors[1][1];
	char *c_selborder = theme->colors[1][2];
	copystr(c_normborder, 8, "#3B4252");
	copystr(c_normbg,     8, "#434C5E");
	copystr(c_normfg,     8, "#D8DEE9");
	copystr(c_selborder,  8, "#81A1C1");
	copystr(c_selbg,      8, "#434C5E");
	copystr(c_selfg,      8, "#ECEFF4");

	char color_section[TOML_MAX_STR] = "colors";
	const TomlValue *vtheme = toml_get(&doc, "active", "theme");
	if (vtheme && vtheme->type == TOML_STRING && vtheme->s[0]) {
		const char prefix[] = "theme.";
		size_t theme_len = strlen(vtheme->s);
		if (theme_len < sizeof(color_section) - (sizeof(prefix) - 1)) {
			memcpy(color_section, prefix, sizeof(prefix) - 1);
			memcpy(color_section + sizeof(prefix) - 1, vtheme->s,
			       theme_len + 1);
		} else {
			fprintf(stderr, "dwm: active theme name is too long; using colors\n");
		}
	}

#define TRY_COLOR(field, dest) do { \
	const TomlValue *_v = toml_get(&doc, color_section, field); \
	if (_v && _v->type == TOML_STRING && strlen(_v->s) >= 4) { \
		strncpy(dest, _v->s, 7); dest[7] = '\0'; \
	} } while (0)

	TRY_COLOR("normbordercolor", c_normborder);
	TRY_COLOR("normbgcolor",     c_normbg);
	TRY_COLOR("normfgcolor",     c_normfg);
	TRY_COLOR("selbordercolor",  c_selborder);
	TRY_COLOR("selbgcolor",      c_selbg);
	TRY_COLOR("selfgcolor",      c_selfg);
#undef TRY_COLOR

	theme->borderpx = -1;
	const TomlValue *vbpx = toml_get(&doc, "appearance", "borderpx");
	if (vbpx && vbpx->type == TOML_INT && vbpx->i >= 0)
		theme->borderpx = vbpx->i;

	fprintf(stderr, "dwm: loaded theme from config\n");
	return 1;
}

static void
load_rules_toml(const char *user_path, const char *default_path)
{
	static TomlDoc doc;
	static int from_config;

	if (!toml_load_with_fallback(&doc, user_path, default_path, "rules", NULL, from_config))
		return;
	from_config = 1;
	int n = toml_table_count(&doc, "rules");
	if (n > TOML_RULES_MAX) n = TOML_RULES_MAX;
	int nk = 0;
	for (int i = 0; i < n; i++) {
		const TomlValue *vc    = toml_table_get(&doc, "rules", i, "class");
		const TomlValue *vi    = toml_table_get(&doc, "rules", i, "instance");
		const TomlValue *vt    = toml_table_get(&doc, "rules", i, "title");
		const TomlValue *vtag  = toml_table_get(&doc, "rules", i, "tags");
		const TomlValue *vfl   = toml_table_get(&doc, "rules", i, "isfloating");
		const TomlValue *vaot  = toml_table_get(&doc, "rules", i, "alwaysontop");
		const TomlValue *vterm = toml_table_get(&doc, "rules", i, "isterminal");
		const TomlValue *vno   = toml_table_get(&doc, "rules", i, "noswallow");
		const TomlValue *vmon  = toml_table_get(&doc, "rules", i, "monitor");
		Rule *r = &rt_rules_buf[nk];
		if (vc && vc->type == TOML_STRING && vc->s[0]) {
			copystr(rt_rules_strbuf[nk*3+0], TOML_MAX_STR, vc->s);
			r->class = rt_rules_strbuf[nk*3+0];
		} else {
			r->class = NULL;
		}
		if (vi && vi->type == TOML_STRING && vi->s[0]) {
			copystr(rt_rules_strbuf[nk*3+1], TOML_MAX_STR, vi->s);
			r->instance = rt_rules_strbuf[nk*3+1];
		} else {
			r->instance = NULL;
		}
		if (vt && vt->type == TOML_STRING && vt->s[0]) {
			copystr(rt_rules_strbuf[nk*3+2], TOML_MAX_STR, vt->s);
			r->title = rt_rules_strbuf[nk*3+2];
		} else {
			r->title = NULL;
		}
		/* A rule with nothing to match would apply to every window and reset
		 * the flags every earlier rule set (Sync Sprint 12 S12-05). */
		if (!r->class && !r->instance && !r->title) {
			fprintf(stderr, "dwm: window rule %d has no class, instance or title; skipped\n", i + 1);
			continue;
		}
		r->tags       = (vtag  && vtag->type  == TOML_INT && vtag->i >= 1 && vtag->i <= 9)
		                ? (unsigned int)(1 << (vtag->i - 1)) : 0;
		r->isfloating = (vfl   && vfl->type   == TOML_INT) ? (int)vfl->i           : 0;
		r->alwaysontop = (vaot && vaot->type  == TOML_INT) ? (int)vaot->i          : 0;
		r->isterminal = (vterm && vterm->type == TOML_INT) ? (int)vterm->i         : 0;
		r->noswallow  = (vno   && vno->type   == TOML_INT) ? (int)vno->i           : 0;
		r->monitor    = (vmon  && vmon->type  == TOML_INT) ? (int)vmon->i          : -1;
		nk++;
	}
	rt_rules  = rt_rules_buf;
	rt_nrules = nk;
	fprintf(stderr, "dwm: loaded %d window rules from config\n", nk);
}

int
runtime_config_load(ConfigTheme *theme)
{
	int themed;

	runtime_config_ensure_user_watch();
	load_hotkeys_toml(toml_hotkeys_path, toml_hotkeys_default_path);
	themed = load_themes_toml(toml_themes_path, toml_themes_default_path, theme);
	load_rules_toml(toml_rules_path,     toml_rules_default_path);
	return themed;
}

int
runtime_config_fd(void)
{
	return inotify_fd;
}

void
runtime_config_mark_reload_pending(void)
{
	sig_reload_pending = 1;
}

int
runtime_config_poll(void)
{
	char ibuf[4096];
	ssize_t nr = read(inotify_fd, ibuf, sizeof(ibuf));
	int need_reload = 0, themes_changed = 0;
	char *ptr = ibuf;
	char *end;

	if (nr <= 0)
		return 0;
	end = ibuf + nr;

	while (ptr + sizeof(struct inotify_event) <= end) {
		struct inotify_event *ie = (struct inotify_event *)ptr;
		if (ptr + sizeof(struct inotify_event) + ie->len > end)
			break;
		/* The lyona directory was deleted (the kernel drops the watch) or moved
		 * away (the watch would follow it): forget it, so the parent watch
		 * below can watch the directory that replaces it. */
		if (ie->wd == inotify_wd && (ie->mask & (IN_IGNORED | IN_MOVE_SELF))) {
			if (!(ie->mask & IN_IGNORED))
				inotify_rm_watch(inotify_fd, inotify_wd);
			inotify_wd = -1;
			ptr += sizeof(struct inotify_event) + ie->len;
			continue;
		}
		/* A lyona directory appeared in the config home: watch it, and load it. */
		if (ie->wd == inotify_wd_parent) {
			if (ie->len > 0 && (ie->mask & IN_ISDIR) && strcmp(ie->name, "lyona") == 0) {
				runtime_config_ensure_user_watch();
				need_reload = themes_changed = 1;
			}
			ptr += sizeof(struct inotify_event) + ie->len;
			continue;
		}
		if (ie->len > 0 &&
		    (strcmp(ie->name, "hotkeys.toml")      == 0 ||
		     strcmp(ie->name, "themes.toml")       == 0 ||
		     strcmp(ie->name, "window-rules.toml") == 0))
			need_reload = 1;
		if (ie->len > 0 && strcmp(ie->name, "themes.toml") == 0)
			themes_changed = 1;
		ptr += sizeof(struct inotify_event) + ie->len;
	}
	if (!need_reload)
		return 0;
	return CONFIG_RELOAD | (themes_changed ? CONFIG_THEMES : 0);
}

static void
runtime_config_ensure_user_watch(void)
{
	if (inotify_wd >= 0 || toml_config_dir[0] == '\0')
		return;
	if (inotify_fd < 0) {
		setup_inotify();
		return;
	}
	inotify_wd = inotify_add_watch(inotify_fd, toml_config_dir, USER_CONFIG_WATCH);
	if (inotify_wd < 0)
		inotify_wd = -1;
}

int
runtime_config_take_pending(void)
{
	if (!sig_reload_pending)
		return 0;
	sig_reload_pending = 0;
	return 1;
}

void
runtime_config_setup(const ConfigEnv *e)
{
	env = e;
	spawnfunc = lookup_func("spawn");
	setup_inotify();
}

static void
setup_inotify(void)
{
	const char *home = getenv("HOME");
	const char *config_home = getenv("XDG_CONFIG_HOME");
	const char *data_home = getenv("XDG_DATA_HOME");
	char config_home_fallback[PATH_MAX];
	char data_home_fallback[PATH_MAX];
	if (((!config_home || config_home[0] != '/')
	     || (!data_home || data_home[0] != '/'))
	    && (!home || home[0] == '\0')) {
		fprintf(stderr, "dwm: HOME is required for XDG fallback paths\n");
		return;
	}

	if (!config_home || config_home[0] != '/') {
		if (!pathjoin(config_home_fallback, sizeof(config_home_fallback),
		              home, ".config")) {
			fprintf(stderr, "dwm: config home path exceeds PATH_MAX\n");
			return;
		}
		config_home = config_home_fallback;
	}
	if (!data_home || data_home[0] != '/') {
		if (!pathjoin(data_home_fallback, sizeof(data_home_fallback),
		              home, ".local/share")) {
			fprintf(stderr, "dwm: data home path exceeds PATH_MAX\n");
			return;
		}
		data_home = data_home_fallback;
	}
	copystr(dwm_config_home_dir, sizeof(dwm_config_home_dir), config_home);
	copystr(dwm_data_home_dir, sizeof(dwm_data_home_dir), data_home);
	if (setenv("XDG_CONFIG_HOME", dwm_config_home_dir, 1) < 0 ||
	    setenv("XDG_DATA_HOME", dwm_data_home_dir, 1) < 0) {
		perror("dwm: cannot normalize XDG environment");
		return;
	}

	if (!pathjoin(toml_config_dir, sizeof(toml_config_dir),
	              config_home, "lyona")
	    || !pathjoin(toml_hotkeys_path, sizeof(toml_hotkeys_path),
	                 toml_config_dir, "hotkeys.toml")
	    || !pathjoin(toml_themes_path, sizeof(toml_themes_path),
	                 toml_config_dir, "themes.toml")
	    || !pathjoin(toml_rules_path, sizeof(toml_rules_path),
	                 toml_config_dir, "window-rules.toml")) {
		fprintf(stderr, "dwm: user config path exceeds PATH_MAX\n");
		return;
	}

	if (!default_config_dir(toml_default_dir, sizeof(toml_default_dir))) {
		/* Empty paths: the loaders treat them as missing, and the watch
		 * below fails harmlessly. */
		fprintf(stderr, "dwm: cannot find the shipped default config\n");
		toml_default_dir[0] = '\0';
	} else if (!pathjoin(toml_hotkeys_default_path,
	                 sizeof(toml_hotkeys_default_path),
	                 toml_default_dir, "hotkeys.toml")
	    || !pathjoin(toml_themes_default_path,
	                 sizeof(toml_themes_default_path),
	                 toml_default_dir, "themes.toml")
	    || !pathjoin(toml_rules_default_path,
	                 sizeof(toml_rules_default_path),
	                 toml_default_dir, "window-rules.toml")) {
		fprintf(stderr, "dwm: default config path exceeds PATH_MAX\n");
		return;
	} else {
		fprintf(stderr, "dwm: shipped defaults from %s\n", toml_default_dir);
	}

	inotify_fd = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
	if (inotify_fd < 0) { perror("dwm: inotify_init1"); return; }

	inotify_wd = inotify_add_watch(inotify_fd, toml_config_dir, USER_CONFIG_WATCH);
	if (inotify_wd < 0) {

		inotify_wd = -1;
	}
	inotify_wd_parent = dwm_config_home_dir[0]
	                    ? inotify_add_watch(inotify_fd, dwm_config_home_dir,
	                                        IN_CREATE | IN_MOVED_TO | IN_ONLYDIR)
	                    : -1;

	inotify_wd3 = toml_default_dir[0]
	              ? inotify_add_watch(inotify_fd, toml_default_dir,
	                                  IN_CLOSE_WRITE | IN_MOVED_TO)
	              : -1;

	if (inotify_wd < 0 && inotify_wd3 < 0 && inotify_wd_parent < 0) {

		close(inotify_fd);
		inotify_fd = -1;
		return;
	}

}

