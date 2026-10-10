/* Minimal TOML parser for lyona hot-reload configuration.
 * Supports: string, integer, float, string arrays,
 *           [section], [[array-of-tables]]
 * Comments (#), basic string escapes (\n \t \\ \")
 */
#pragma once
#include <stddef.h>

#define TOML_MAX_ENTRIES 512
#define TOML_MAX_STR     512
#define TOML_MAX_ARR      32
#define TOML_MAX_LINE   4096 /* bytes in one line, its newline included */

typedef enum {
	TOML_STRING = 0,
	TOML_INT,
	TOML_FLOAT,
	TOML_ARRAY
} TomlType;

typedef struct {
	TomlType type;
	int      is_bool; /* a TOML_INT that was written true or false */
	char     s[TOML_MAX_STR];
	long     i;
	double   d;
	struct {
		char  items[TOML_MAX_ARR][TOML_MAX_STR];
		int   len;
	} a;
} TomlValue;

typedef struct {
	char      section[TOML_MAX_STR];
	int       table_idx;
	char      key[TOML_MAX_STR];
	TomlValue val;
} TomlEntry;

typedef struct {
	TomlEntry entries[TOML_MAX_ENTRIES];
	int       n;
	int       truncated; /* entries past TOML_MAX_ENTRIES were dropped */
	int       long_lines; /* lines longer than TOML_MAX_LINE, each skipped whole */
	int       bad_lines;      /* lines with text the parser could not read (#319) */
	int       first_bad_line; /* the first of them, 1-based; 0 when none */
	int       long_arrays;    /* arrays cut to TOML_MAX_ARR items */
	int       unclosed_line;  /* where an array opened that never closed; 0 when none */
} TomlDoc;

int toml_parse(const char *path, TomlDoc *doc);

const TomlValue *toml_get(const TomlDoc *doc, const char *section,
                          const char *key);

int toml_table_count(const TomlDoc *doc, const char *section);

const TomlValue *toml_table_get(const TomlDoc *doc, const char *section,
                                int idx, const char *key);
