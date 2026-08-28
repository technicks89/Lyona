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

typedef enum {
	TOML_STRING = 0,
	TOML_INT,
	TOML_FLOAT,
	TOML_ARRAY
} TomlType;

typedef struct {
	TomlType type;
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
} TomlDoc;

int toml_parse(const char *path, TomlDoc *doc);

const TomlValue *toml_get(const TomlDoc *doc, const char *section,
                          const char *key);

int toml_table_count(const TomlDoc *doc, const char *section);

const TomlValue *toml_table_get(const TomlDoc *doc, const char *section,
                                int idx, const char *key);
