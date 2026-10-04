/* See LICENSE file for copyright and license details.
 * Minimal TOML parser for lyona hot-reload configuration.
 */
#include "tomlparser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "util.h"

static char *
strtrim(char *s)
{
	while (isspace((unsigned char)*s)) s++;
	if (*s) {
		char *e = s + strlen(s) - 1;
		while (e > s && isspace((unsigned char)*e)) *e-- = '\0';
	}
	return s;
}

static const char *parse_inline_table(const char *p, TomlDoc *doc,
                                      const char *section, int tidx);

/* Cut a "#" comment off a line, but not a "#" inside a double-quoted string
 * (where a backslash escapes the next character). Sync Sprint 12 S12-05. */
static void
strip_comment(char *s)
{
	int in_str = 0;

	for (; *s; s++) {
		if (in_str && *s == '\\' && s[1]) {
			s++;
			continue;
		}
		if (*s == '"')
			in_str = !in_str;
		else if (!in_str && *s == '#') {
			*s = '\0';
			return;
		}
	}
}

/* TOML's true and false, as the integers the dwm loaders read. */
static int
parse_bool(const char *s, long *out)
{
	if (strcmp(s, "true") == 0) { *out = 1; return 1; }
	if (strcmp(s, "false") == 0) { *out = 0; return 1; }
	return 0;
}

/* Parse the tables on one line of a multi-line array, from sp. Returns 1 when
 * the line also closes the array with "]". */
static int
parse_array_line(const char *sp, TomlDoc *doc, const char *section, int *tidx)
{
	while (*sp) {
		if (*sp == ']')
			return 1;
		if (*sp == '{') {
			sp = parse_inline_table(sp + 1, doc, section, (*tidx)++);
			continue;
		}
		sp++;
	}
	return 0;
}

int
toml_table_count(const TomlDoc *doc, const char *section)
{
	int max = -1, i;
	for (i = 0; i < doc->n; i++)
		if (doc->entries[i].table_idx >= 0
		    && strcmp(doc->entries[i].section, section) == 0
		    && doc->entries[i].table_idx > max)
			max = doc->entries[i].table_idx;
	return max + 1;
}

static const char *
unescape_into(const char *src, char *dst, int maxlen)
{
	int si = 0;
	while (*src && *src != '"' && si < maxlen - 1) {
		if (*src == '\\' && *(src + 1)) {
			src++;
			switch (*src) {
			case 'n':  dst[si++] = '\n'; break;
			case 't':  dst[si++] = '\t'; break;
			case '\\': dst[si++] = '\\'; break;
			case '"':  dst[si++] = '"';  break;
			default:   dst[si++] = *src; break;
			}
		} else {
			dst[si++] = *src;
		}
		src++;
	}
	dst[si] = '\0';
	/* A string longer than dst is truncated, but read to its closing quote,
	 * so its tail is never parsed as keys or values (Sync Sprint 16 R16-08). */
	while (*src && *src != '"') {
		if (*src == '\\' && *(src + 1))
			src++;
		src++;
	}
	return src;
}

static const char *
parse_inline_table(const char *p, TomlDoc *doc, const char *section, int tidx)
{
	while (*p) {

		while (isspace((unsigned char)*p) || *p == ',') p++;
		if (*p == '}' || *p == '\0') break;
		if (doc->n >= TOML_MAX_ENTRIES) {
			doc->truncated = 1;
			break;
		}

		const char *kstart = p;
		while (*p && *p != '=' && !isspace((unsigned char)*p) && *p != '}') p++;
		int klen = (int)(p - kstart);
		if (klen <= 0 || klen >= TOML_MAX_STR) break;
		while (isspace((unsigned char)*p)) p++;
		if (*p != '=') break;
		p++;
		while (isspace((unsigned char)*p)) p++;

		TomlEntry *ent = &doc->entries[doc->n];
		ent->val.is_bool = 0;
		strncpy(ent->section, section, TOML_MAX_STR - 1);
		ent->section[TOML_MAX_STR - 1] = '\0';
		ent->table_idx = tidx;
		strncpy(ent->key, kstart, (size_t)klen);
		ent->key[klen] = '\0';

		if (*p == '"') {
			ent->val.type = TOML_STRING;
			p = unescape_into(p + 1, ent->val.s, TOML_MAX_STR);
			if (*p == '"') p++;

		} else if (*p == '[') {
			ent->val.type = TOML_ARRAY;
			ent->val.a.len = 0;
			p++;
			while (*p && *p != ']' && ent->val.a.len < TOML_MAX_ARR) {
				while (isspace((unsigned char)*p) || *p == ',') p++;
				if (*p == ']' || *p == '\0') break;
				if (*p == '"') {
					char *dst = ent->val.a.items[ent->val.a.len];
					p = unescape_into(p + 1, dst, TOML_MAX_STR);
					if (*p == '"') p++;
					ent->val.a.len++;
				} else {
					p++;
				}
			}
			if (*p == ']') p++;

		} else {

			char nbuf[64];
			int ni = 0;
			while (*p && *p != ',' && *p != '}' && !isspace((unsigned char)*p) && ni < 63)
				nbuf[ni++] = *p++;
			nbuf[ni] = '\0';
			char *ep;
			long iv;
			if (parse_bool(nbuf, &iv)) {
				ent->val.type = TOML_INT;
				ent->val.is_bool = 1;
				ent->val.i = iv;
			} else if ((iv = strtol(nbuf, &ep, 10)), ep != nbuf && *ep == '\0') {
				ent->val.type = TOML_INT;
				ent->val.i = iv;
			} else {
				double dv = strtod(nbuf, &ep);
				ent->val.type = TOML_FLOAT;
				ent->val.d = dv;
			}
		}
		doc->n++;

		while (*p && *p != ',' && *p != '}') p++;
	}
	if (*p == '}') p++;
	return p;
}

/* A config file is a regular file of a sane size. Opened without blocking, so a
 * FIFO cannot stall dwm at open, then checked, so a device (a symlink to
 * /dev/zero, say) or a huge file cannot keep the parser reading forever. */
#define TOML_MAX_FILE_BYTES (1024L * 1024L)

static FILE *
toml_open(const char *path)
{
	struct stat st;
	FILE *f;
	int fd, flags;

	if ((fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)) < 0)
		return NULL;
	if (fstat(fd, &st) < 0 || !S_ISREG(st.st_mode) || st.st_size > TOML_MAX_FILE_BYTES
	    || (flags = fcntl(fd, F_GETFL)) < 0 || fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0) {
		close(fd);
		return NULL;
	}
	if (!(f = fdopen(fd, "r")))
		close(fd);
	return f;
}

int
toml_parse(const char *path, TomlDoc *doc)
{
	FILE *f = toml_open(path);
	if (!f) return 0;
	doc->n = 0;
	doc->truncated = 0;
	char line[4096];
	char cur_section[TOML_MAX_STR] = "";
	int  cur_tidx = -1;

	int  ml_active = 0;
	char ml_section[TOML_MAX_STR] = "";
	int  ml_tidx   = 0;
	long total     = 0;

	while (fgets(line, sizeof(line), f)) {
		/* toml_open checked the size, but the file can still grow while it is
		 * read; stop at the same limit rather than read without end. */
		total += (long)strlen(line);
		if (total > TOML_MAX_FILE_BYTES) {
			fclose(f);
			return 0;
		}
		char *p = strtrim(line);

		if (ml_active) {
			strip_comment(p);
			if (parse_array_line(p, doc, ml_section, &ml_tidx))
				ml_active = 0;
			continue;
		}

		if (!*p || *p == '#') continue;

		if (p[0] == '[' && p[1] == '[') {
			char *end = strstr(p + 2, "]]");
			if (!end) continue;
			int len = (int)(end - (p + 2));
			if (len >= TOML_MAX_STR) len = TOML_MAX_STR - 1;
			strncpy(cur_section, p + 2, len);
			cur_section[len] = '\0';
			cur_tidx = toml_table_count(doc, cur_section);
			continue;
		}

		if (p[0] == '[') {
			char *end = strchr(p + 1, ']');
			if (!end) continue;
			int len = (int)(end - (p + 1));
			if (len >= TOML_MAX_STR) len = TOML_MAX_STR - 1;
			strncpy(cur_section, p + 1, len);
			cur_section[len] = '\0';
			cur_tidx = -1;
			continue;
		}

		char *eq = strchr(p, '=');
		if (!eq) continue;

		int klen = (int)(eq - p);
		while (klen > 0 && isspace((unsigned char)p[klen - 1])) klen--;
		if (klen <= 0 || klen >= TOML_MAX_STR) continue;
		char key[TOML_MAX_STR];
		strncpy(key, p, (size_t)klen);
		key[klen] = '\0';

		char *v = strtrim(eq + 1);

		strip_comment(v);
		v = strtrim(v);

		if (*v == '[') {
			const char *after = v + 1;
			while (isspace((unsigned char)*after)) after++;

			if (*after == '\0') {

				strncpy(ml_section, key, TOML_MAX_STR - 1);
				ml_section[TOML_MAX_STR - 1] = '\0';
				ml_tidx   = 0;
				ml_active = 1;
				continue;
			}

			if (*after == '{') {
				int tidx_local = 0;

				/* Not closed on this line: the rest of the array follows. */
				if (!parse_array_line(v + 1, doc, key, &tidx_local)) {
					copystr(ml_section, sizeof(ml_section), key);
					ml_tidx   = tidx_local;
					ml_active = 1;
				}
				continue;
			}
		}

		/* Recorded, not silent: dwm and lyona-toml report it (S12-14). */
		if (doc->n >= TOML_MAX_ENTRIES) {
			doc->truncated = 1;
			continue;
		}
		TomlEntry *ent = &doc->entries[doc->n];
		ent->val.is_bool = 0;
		copystr(ent->section, sizeof(ent->section), cur_section);
		ent->table_idx = cur_tidx;
		copystr(ent->key, sizeof(ent->key), key);

		if (*v == '"') {
			ent->val.type = TOML_STRING;
			const char *sp = unescape_into(v + 1, ent->val.s, TOML_MAX_STR);
			(void)sp;

		} else if (*v == '[') {
			ent->val.type = TOML_ARRAY;
			ent->val.a.len = 0;
			const char *vp = v + 1;
			while (*vp && *vp != ']' && ent->val.a.len < TOML_MAX_ARR) {
				while (isspace((unsigned char)*vp) || *vp == ',') vp++;
				if (*vp == ']' || *vp == '\0') break;
				if (*vp == '"') {
					char *dst = ent->val.a.items[ent->val.a.len];
					vp = unescape_into(vp + 1, dst, TOML_MAX_STR);
					if (*vp == '"') vp++;
					ent->val.a.len++;
				} else {
					vp++;
				}
			}

		} else {
			char *ep;
			long iv;
			if (parse_bool(v, &iv)) {
				ent->val.type = TOML_INT;
				ent->val.is_bool = 1;
				ent->val.i = iv;
			} else if ((iv = strtol(v, &ep, 10)), ep != v && (*ep == '\0' || *ep == '#' || isspace((unsigned char)*ep))) {
				ent->val.type = TOML_INT;
				ent->val.i = iv;
			} else {
				double dv = strtod(v, &ep);
				if (ep != v) {
					ent->val.type = TOML_FLOAT;
					ent->val.d = dv;
				} else {
					ent->val.type = TOML_STRING;
					strncpy(ent->val.s, v, TOML_MAX_STR - 1);
					ent->val.s[TOML_MAX_STR - 1] = '\0';
				}
			}
		}
		doc->n++;
	}
	fclose(f);
	return 1;
}

const TomlValue *
toml_get(const TomlDoc *doc, const char *section, const char *key)
{
	int i;
	for (i = 0; i < doc->n; i++) {
		const TomlEntry *e = &doc->entries[i];
		if (e->table_idx < 0
		    && strcmp(e->section, section) == 0
		    && strcmp(e->key, key) == 0)
			return &e->val;
	}
	return NULL;
}

const TomlValue *
toml_table_get(const TomlDoc *doc, const char *section, int idx, const char *key)
{
	int i;
	for (i = 0; i < doc->n; i++) {
		const TomlEntry *e = &doc->entries[i];
		if (e->table_idx == idx
		    && strcmp(e->section, section) == 0
		    && strcmp(e->key, key) == 0)
			return &e->val;
	}
	return NULL;
}
