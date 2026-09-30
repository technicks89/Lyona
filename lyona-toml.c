/* lyona-toml: the one reader of Lyona's TOML files for scripts (Sync Sprint 12
 * S12-14, decision D-20). It uses dwm's own parser, so a file means the same
 * to a script as it does to dwm.
 *
 *   lyona-toml dump FILE
 *       One line per entry, in file order:
 *           SECTION TAB INDEX TAB KEY TAB VALUE
 *       INDEX is the [[array-of-tables]] index, or -1. A boolean is written
 *       true or false, a number as dwm reads it, and an array's items joined
 *       by US (0x1f). Tab, newline, carriage return and backslash inside a
 *       value, section or key are written \t, \n, \r and \\, so a line is
 *       always one record.
 *   lyona-toml get FILE SECTION KEY
 *       The value alone (the same encoding), as dwm's toml_get finds it: the
 *       first plain entry of that section and key.
 *
 * Exit status: 0 read, 1 key absent (get), 2 usage, 3 the file could not be
 * read or parsed, 4 the file has more entries than dwm keeps. With 4 the
 * output is still written, and holds what dwm would see. */
#include <stdio.h>
#include <string.h>

#include "tomlparser.h"

static TomlDoc doc; /* about 9 MB: static, not on the stack */

static void
put_escaped(const char *s)
{
	for (; *s; s++) {
		switch (*s) {
		case '\t': fputs("\\t", stdout); break;
		case '\n': fputs("\\n", stdout); break;
		case '\r': fputs("\\r", stdout); break;
		case '\\': fputs("\\\\", stdout); break;
		default: putchar((unsigned char)*s); break;
		}
	}
}

static void
put_value(const TomlValue *v)
{
	int i;

	switch (v->type) {
	case TOML_STRING:
		put_escaped(v->s);
		break;
	case TOML_INT:
		if (v->is_bool)
			fputs(v->i ? "true" : "false", stdout);
		else
			printf("%ld", v->i);
		break;
	case TOML_FLOAT:
		printf("%.17g", v->d);
		break;
	case TOML_ARRAY:
		for (i = 0; i < v->a.len; i++) {
			if (i > 0)
				putchar('\x1f');
			put_escaped(v->a.items[i]);
		}
		break;
	}
}

static int
usage(void)
{
	fputs("usage: lyona-toml dump FILE\n"
	      "       lyona-toml get FILE SECTION KEY\n", stderr);
	return 2;
}

int
main(int argc, char *argv[])
{
	const TomlValue *v;
	int i;

	if (argc < 3)
		return usage();
	if (strcmp(argv[1], "dump") == 0) {
		if (argc != 3)
			return usage();
	} else if (strcmp(argv[1], "get") == 0) {
		if (argc != 5)
			return usage();
	} else {
		return usage();
	}
	if (!toml_parse(argv[2], &doc)) {
		fprintf(stderr, "lyona-toml: cannot read %s\n", argv[2]);
		return 3;
	}

	if (argv[1][0] == 'd') {
		for (i = 0; i < doc.n; i++) {
			put_escaped(doc.entries[i].section);
			printf("\t%d\t", doc.entries[i].table_idx);
			put_escaped(doc.entries[i].key);
			putchar('\t');
			put_value(&doc.entries[i].val);
			putchar('\n');
		}
	} else {
		if (!(v = toml_get(&doc, argv[3], argv[4])))
			return doc.truncated ? 4 : 1;
		put_value(v);
		putchar('\n');
	}
	if (fflush(stdout) != 0 || ferror(stdout)) {
		fputs("lyona-toml: write error\n", stderr);
		return 3;
	}
	if (doc.truncated) {
		fprintf(stderr, "lyona-toml: %s has more than %d entries; the rest were ignored\n",
		        argv[2], TOML_MAX_ENTRIES);
		return 4;
	}
	return 0;
}
