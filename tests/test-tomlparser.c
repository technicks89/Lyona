/* Sync Sprint 12 S12-05: unit tests for tomlparser.c, the parser dwm uses for
 * hotkeys.toml, themes.toml and window-rules.toml.
 *
 *   test-tomlparser WORKDIR HOTKEYS KEYS TAG_KEYS BUTTONS RULES_FILE RULES THEMES
 *
 * WORKDIR receives the small files each case writes. The remaining arguments are
 * the shipped files and the number of tables tests/test-tomlparser.sh counted in
 * each array, which the parser must reproduce exactly. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../tomlparser.h"

static TomlDoc doc; /* about 9 MB: never on the stack */
static int failures;
static char path[4096];

#define CHECK(cond, ...) do { \
	if (!(cond)) { \
		failures++; \
		fprintf(stderr, "FAIL (%s:%d): ", __func__, __LINE__); \
		fprintf(stderr, __VA_ARGS__); \
		fputc('\n', stderr); \
	} \
} while (0)

static int
parse_text(const char *dir, const char *name, const char *text)
{
	FILE *f;

	snprintf(path, sizeof path, "%s/%s.toml", dir, name);
	if (!(f = fopen(path, "w")) || fputs(text, f) < 0 || fclose(f) != 0) {
		perror(path);
		exit(2);
	}
	return toml_parse(path, &doc);
}

static const char *
table_str(const char *section, int idx, const char *key)
{
	const TomlValue *v = toml_table_get(&doc, section, idx, key);
	return v && v->type == TOML_STRING ? v->s : NULL;
}

static int
is_int(const TomlValue *v, long want)
{
	return v && v->type == TOML_INT && v->i == want;
}

static int
is_str(const TomlValue *v, const char *want)
{
	return v && v->type == TOML_STRING && strcmp(v->s, want) == 0;
}

/* A "{" inside a trailing comment used to open a phantom table: a rule with no
 * class, instance or title, which matches every window. */
static void
comment_brace(const char *dir)
{
	CHECK(parse_text(dir, "comment-brace",
		"rules = [\n"
		"  { class=\"a\", isfloating=1 }, # see {docs}\n"
		"  # { class=\"commented\" },\n"
		"  { class=\"b\" },\n"
		"]\n"
		"[active]\n"
		"theme = \"x\"\n"), "did not parse");
	CHECK(toml_table_count(&doc, "rules") == 2, "rules: %d tables, want 2",
	      toml_table_count(&doc, "rules"));
	CHECK(table_str("rules", 0, "class") && !strcmp(table_str("rules", 0, "class"), "a"), "rule 0 class");
	CHECK(table_str("rules", 1, "class") && !strcmp(table_str("rules", 1, "class"), "b"), "rule 1 class");
	CHECK(is_str(toml_get(&doc, "active", "theme"), "x"), "the section after the array was lost");
}

/* Closing the array on the line of its last table used to leave the parser in
 * array mode, swallowing every later section. */
static void
same_line_close(const char *dir)
{
	CHECK(parse_text(dir, "same-line-close",
		"rules = [\n"
		"  { class=\"a\" },\n"
		"  { class=\"b\" } ]\n"
		"[active]\n"
		"theme = \"y\"\n"), "did not parse");
	CHECK(toml_table_count(&doc, "rules") == 2, "rules: %d tables, want 2",
	      toml_table_count(&doc, "rules"));
	CHECK(is_str(toml_get(&doc, "active", "theme"), "y"), "the section after the array was lost");
}

/* An array whose first table is on the opening line, continued below. */
static void
first_line_table(const char *dir)
{
	CHECK(parse_text(dir, "first-line-table",
		"rules = [ { class=\"a\" },\n"
		"  { class=\"b\" },\n"
		"]\n"
		"after = 3\n"), "did not parse");
	CHECK(toml_table_count(&doc, "rules") == 2, "rules: %d tables, want 2",
	      toml_table_count(&doc, "rules"));
	CHECK(table_str("rules", 1, "class") && !strcmp(table_str("rules", 1, "class"), "b"), "rule 1 class");
	CHECK(is_int(toml_get(&doc, "", "after"), 3), "the key after the array was lost or garbled");
}

/* true and false: loaders only take integers, so they must parse as 1 and 0. */
static void
booleans(const char *dir)
{
	CHECK(parse_text(dir, "booleans",
		"flag = true\n"
		"off = false # comment\n"
		"rules = [\n"
		"  { class=\"a\", isfloating=true },\n"
		"  { class=\"b\", isfloating=false, noswallow=1 },\n"
		"]\n"), "did not parse");
	CHECK(is_int(toml_get(&doc, "", "flag"), 1), "top-level true is not integer 1");
	CHECK(is_int(toml_get(&doc, "", "off"), 0), "top-level false is not integer 0");
	CHECK(is_int(toml_table_get(&doc, "rules", 0, "isfloating"), 1), "inline true is not integer 1");
	CHECK(is_int(toml_table_get(&doc, "rules", 1, "isfloating"), 0), "inline false is not integer 0");
	CHECK(is_int(toml_table_get(&doc, "rules", 1, "noswallow"), 1), "inline integer after a boolean");
}

/* A "#" inside a string is not a comment, even after an escaped quote. */
static void
escaped_quote(const char *dir)
{
	CHECK(parse_text(dir, "escaped-quote",
		"a = \"x \\\" y # not a comment\" # a comment\n"
		"b = \"plain # text\"\n"), "did not parse");
	CHECK(is_str(toml_get(&doc, "", "a"), "x \" y # not a comment"), "escaped quote: '%s'",
	      toml_get(&doc, "", "a") ? toml_get(&doc, "", "a")->s : "(missing)");
	CHECK(is_str(toml_get(&doc, "", "b"), "plain # text"), "hash inside a string");
}

/* A string longer than the parser's buffer is truncated, and read to its
 * closing quote: its tail never becomes keys (Sync Sprint 16 R16-08). */
static void
long_string(const char *dir)
{
	char text[4096], filler[701];

	memset(filler, 'x', 600);
	filler[600] = '\0';
	snprintf(text, sizeof(text),
		"rules = [\n"
		"  { class=\"%s, isfloating=1, tags=9\", monitor=2 },\n"
		"]\n"
		"title = \"%s \\\" still the string\"\n"
		"after = 7\n", filler, filler);
	CHECK(parse_text(dir, "long-string", text), "did not parse");
	CHECK(toml_table_count(&doc, "rules") == 1, "rules: %d tables, want 1",
	      toml_table_count(&doc, "rules"));
	CHECK(!toml_table_get(&doc, "rules", 0, "isfloating"), "a long string's tail became an isfloating key");
	CHECK(!toml_table_get(&doc, "rules", 0, "tags"), "a long string's tail became a tags key");
	CHECK(is_int(toml_table_get(&doc, "rules", 0, "monitor"), 2), "the key after a long string was lost");
	CHECK(table_str("rules", 0, "class") && strlen(table_str("rules", 0, "class")) == TOML_MAX_STR - 1,
	      "the long string was not truncated to the buffer");
	CHECK(is_int(toml_get(&doc, "", "after"), 7), "the key after a long top-level string was lost");
}

static int
parse_bytes(const char *dir, const char *name, const char *bytes, size_t len)
{
	FILE *f;

	snprintf(path, sizeof path, "%s/%s.toml", dir, name);
	if (!(f = fopen(path, "w")) || fwrite(bytes, 1, len, f) != len || fclose(f) != 0) {
		perror(path);
		exit(2);
	}
	return toml_parse(path, &doc);
}

/* A line longer than the parser's line buffer is skipped whole and counted:
 * its remainder used to be read as the next line, so text inside a long
 * string became a key of its own (#271). */
static void
long_line(const char *dir)
{
	static char text[3 * TOML_MAX_LINE], filler[TOML_MAX_LINE];
	int n;

	/* Over the limit: one skipped line, and nothing in its tail is a key. The
	 * filler ends the buffer just before " injected =", where the old parser
	 * cut the line and read the rest as a key. */
	memset(filler, 'x', TOML_MAX_LINE);
	filler[TOML_MAX_LINE - 1 - strlen("browser = \"")] = '\0';
	snprintf(text, sizeof(text),
		"[vars]\n"
		"before = 1\n"
		"browser = \"%s injected = \\\"evil\\\" \"\n"
		"after = 2\n", filler);
	CHECK(parse_text(dir, "long-line", text), "did not parse");
	CHECK(doc.long_lines == 1, "long lines: %d, want 1", doc.long_lines);
	CHECK(!toml_get(&doc, "vars", "injected"), "the tail of a long line became a key");
	CHECK(!toml_get(&doc, "vars", "browser"), "the cut start of a long line was kept");
	CHECK(is_int(toml_get(&doc, "vars", "before"), 1), "the key before a long line was lost");
	CHECK(is_int(toml_get(&doc, "vars", "after"), 2), "the key after a long line was lost");

	/* Exactly TOML_MAX_LINE - 1 bytes and its newline: complete, kept, and the
	 * short line after it is read as it is. */
	n = snprintf(text, sizeof(text), "k = \"");
	memset(text + n, 'y', TOML_MAX_LINE - 1 - n - 1);
	n = TOML_MAX_LINE - 2;
	text[n++] = '"';
	text[n++] = '\n';
	snprintf(text + n, sizeof(text) - (size_t)n, "b = 3\n");
	CHECK(parse_text(dir, "full-line", text), "did not parse");
	CHECK(doc.long_lines == 0, "a line that fits was counted as long");
	CHECK(toml_get(&doc, "", "k") != NULL, "a line that just fits was lost");
	CHECK(is_int(toml_get(&doc, "", "b"), 3), "the line after a full line was lost");

	/* A NUL byte is not a cut line: the next line is not swallowed. */
	CHECK(parse_bytes(dir, "nul-byte", "a = 1\0junk\nb = 4\n", sizeof("a = 1\0junk\nb = 4\n") - 1),
	      "did not parse");
	CHECK(doc.long_lines == 0, "a line with a NUL byte was counted as long");
	CHECK(is_int(toml_get(&doc, "", "b"), 4), "the line after a NUL byte was lost");

	/* The last line, too long and with no newline: skipped, no hang. */
	memset(filler, 'x', TOML_MAX_LINE);
	filler[TOML_MAX_LINE - 1] = '\0';
	snprintf(text, sizeof(text), "a = 5\nlast = \"%s\"", filler);
	CHECK(parse_text(dir, "long-last-line", text), "did not parse");
	CHECK(doc.long_lines == 1, "long last line: %d, want 1", doc.long_lines);
	CHECK(is_int(toml_get(&doc, "", "a"), 5), "the key before a long last line was lost");
	CHECK(!toml_get(&doc, "", "last"), "a long last line was kept");
}

/* What already worked must keep working. */
static void
regressions(const char *dir)
{
	CHECK(parse_text(dir, "regressions",
		"n = 12\n"
		"x = 1.5\n"
		"s = \"text\"\n"
		"list = [\"a\", \"b\"]\n"
		"tag_keys = [ { key=\"1\", tag=0 }, { key=\"2\", tag=1 } ]\n"
		"[sec]\n"
		"k = \"v\"\n"), "did not parse");
	CHECK(is_int(toml_get(&doc, "", "n"), 12), "integer");
	CHECK(toml_get(&doc, "", "x") && toml_get(&doc, "", "x")->type == TOML_FLOAT, "float");
	CHECK(is_str(toml_get(&doc, "", "s"), "text"), "string");
	CHECK(toml_get(&doc, "", "list") && toml_get(&doc, "", "list")->a.len == 2, "string array");
	CHECK(toml_table_count(&doc, "tag_keys") == 2, "single-line array of tables");
	CHECK(is_int(toml_table_get(&doc, "tag_keys", 1, "tag"), 1), "single-line table value");
	CHECK(is_str(toml_get(&doc, "sec", "k"), "v"), "section key");
}

static void
append_text(char *text, size_t size, size_t *off, const char *format, ...)
{
	va_list args;
	int written;

	if (*off >= size) {
		fprintf(stderr, "TOML test fixture buffer exhausted\n");
		exit(2);
	}
	va_start(args, format);
	written = vsnprintf(text + *off, size - *off, format, args);
	va_end(args);
	if (written < 0 || (size_t)written >= size - *off) {
		fprintf(stderr, "TOML test fixture formatting failed or was truncated\n");
		exit(2);
	}
	*off += (size_t)written;
}

/* Sync Sprint 12 S12-14: entries past TOML_MAX_ENTRIES are dropped, and the
 * document says so; before, they vanished without a trace. Both paths that
 * store an entry, a plain key and an inline table, set the flag. A boolean is
 * a TOML_INT marked is_bool, so lyona-toml can write it back as true/false. */
static void
truncation(const char *dir)
{
	static char text[TOML_MAX_ENTRIES * 32 + 256];
	size_t off = 0;
	int i;

	CHECK(parse_text(dir, "small", "[a]\nx = true\ny = 1\n"), "a small file did not parse");
	CHECK(!doc.truncated, "a small file was marked truncated");
	CHECK(toml_get(&doc, "a", "x") && toml_get(&doc, "a", "x")->is_bool, "true is not marked is_bool");
	CHECK(toml_get(&doc, "a", "y") && !toml_get(&doc, "a", "y")->is_bool, "1 is marked is_bool");

	append_text(text, sizeof text, &off, "[a]\n");
	for (i = 0; i < TOML_MAX_ENTRIES + 10; i++)
		append_text(text, sizeof text, &off, "k%d = %d\n", i, i);
	CHECK(parse_text(dir, "long", text), "a long file did not parse");
	CHECK(doc.n == TOML_MAX_ENTRIES, "kept %d entries, not %d", doc.n, TOML_MAX_ENTRIES);
	CHECK(doc.truncated, "dropped entries were not recorded");

	off = 0;
	append_text(text, sizeof text, &off, "keys = [\n");
	for (i = 0; i < TOML_MAX_ENTRIES / 2 + 10; i++)
		append_text(text, sizeof text, &off, "  { a=\"x\", b=%d },\n", i);
	append_text(text, sizeof text, &off, "]\n");
	CHECK(parse_text(dir, "long-tables", text), "a long table array did not parse");
	CHECK(doc.truncated, "entries dropped from inline tables were not recorded");

	CHECK(parse_text(dir, "small-again", "[a]\nx = 1\n") && !doc.truncated,
	      "the flag survived into the next parse");
}

/* #319: what the parser could not read is counted, with the first line, an
 * array over TOML_MAX_ARR items no longer ends the outer array early, and an
 * array that never closes is recorded. Well-formed input reports nothing. */
static void
problems(const char *dir)
{
	char text[8192];
	size_t len;
	int i;

	/* 33 exec arguments, then a second rule: the 33rd "]"-free item and the
	 * "]" of the long array used to end "rules", losing rule B. */
	len = 0;
	append_text(text, sizeof text, &len, "rules = [ { class=\"A\", exec=[");
	for (i = 0; i < 33; i++)
		append_text(text, sizeof text, &len, "%s\"a%d\"", i ? ", " : "", i);
	append_text(text, sizeof text, &len, "] }, { class=\"B\", isfloating=1 } ]\n");
	CHECK(parse_text(dir, "long-array", text), "the long-array file did not parse");
	CHECK(toml_table_count(&doc, "rules") == 2, "long array: %d rules, want 2",
	      toml_table_count(&doc, "rules"));
	CHECK(table_str("rules", 1, "class") && strcmp(table_str("rules", 1, "class"), "B") == 0
	      && is_int(toml_table_get(&doc, "rules", 1, "isfloating"), 1),
	      "the rule after a long array was lost");
	CHECK(doc.long_arrays == 1 && doc.bad_lines == 0 && !doc.unclosed_line,
	      "long array: long_arrays %d, bad_lines %d, unclosed %d", doc.long_arrays, doc.bad_lines,
	      doc.unclosed_line);

	/* A 35th item that looks like a table is part of the array, not a rule. */
	len = 0;
	append_text(text, sizeof text, &len, "rules = [ { class=\"A\", exec=[");
	for (i = 0; i < 34; i++)
		append_text(text, sizeof text, &len, "\"a%d\", ", i);
	append_text(text, sizeof text, &len, "\"{ class = \\\"Evil\\\", isfloating = 1 }\"] } ]\n");
	CHECK(parse_text(dir, "long-array-table", text), "the crafted file did not parse");
	CHECK(toml_table_count(&doc, "rules") == 1, "a crafted array item became a rule: %d rules",
	      toml_table_count(&doc, "rules"));

	/* An array in a table with its "]" missing ends at the table's "}", so the
	 * table after it still loads, short or past TOML_MAX_ARR items. */
	CHECK(parse_text(dir, "unclosed-inner-array",
		"rules = [ { class=\"A\", exec=[\"a\", \"b\" }, { class=\"B\", isfloating=1 } ]\n"),
	      "the unclosed-inner-array file did not parse");
	CHECK(toml_table_count(&doc, "rules") == 2 && table_str("rules", 1, "class")
	      && strcmp(table_str("rules", 1, "class"), "B") == 0,
	      "a table after an unclosed array was lost: %d rules", toml_table_count(&doc, "rules"));
	CHECK(doc.bad_lines == 1 && doc.first_bad_line == 1, "unclosed inner array: bad_lines %d, first %d",
	      doc.bad_lines, doc.first_bad_line);
	len = 0;
	append_text(text, sizeof text, &len, "rules = [ { class=\"A\", exec=[");
	for (i = 0; i < 40; i++)
		append_text(text, sizeof text, &len, "\"a%d\", ", i);
	append_text(text, sizeof text, &len, "\"x\" }, { class=\"B\" } ]\n");
	CHECK(parse_text(dir, "unclosed-long-inner-array", text), "the unclosed long array file did not parse");
	CHECK(toml_table_count(&doc, "rules") == 2 && table_str("rules", 1, "class")
	      && strcmp(table_str("rules", 1, "class"), "B") == 0,
	      "a table after an unclosed long array was lost: %d rules", toml_table_count(&doc, "rules"));
	CHECK(doc.bad_lines == 1 && doc.long_arrays == 1, "unclosed long inner array: bad_lines %d, long_arrays %d",
	      doc.bad_lines, doc.long_arrays);

	CHECK(parse_text(dir, "missing-comma",
		"keys = [\n"
		"  { mod=\"SUPER\", key=\"a\", func=\"view\" },\n"
		"  { mod=\"SUPER\", key=\"b\" func=\"view\" },\n"
		"]\n"), "the missing-comma file did not parse");
	CHECK(doc.bad_lines == 1 && doc.first_bad_line == 3, "missing comma: bad_lines %d, first %d",
	      doc.bad_lines, doc.first_bad_line);

	CHECK(parse_text(dir, "missing-brace",
		"keys = [\n"
		"  { mod=\"SUPER\", key=\"a\", func=\"view\" },\n"
		"  { mod=\"SUPER\", key=\"b\", func=\"view\"\n"
		"  { mod=\"SUPER\", key=\"c\", func=\"view\" },\n"
		"]\n"), "the missing-brace file did not parse");
	CHECK(doc.bad_lines == 1 && doc.first_bad_line == 3, "missing brace: bad_lines %d, first %d",
	      doc.bad_lines, doc.first_bad_line);
	CHECK(toml_table_count(&doc, "keys") == 3, "missing brace: %d keys, want 3",
	      toml_table_count(&doc, "keys"));

	CHECK(parse_text(dir, "stray-line", "[a]\nx = 1\noops\n[b\ny = 2\n"),
	      "the stray-line file did not parse");
	CHECK(doc.bad_lines == 2 && doc.first_bad_line == 3, "stray lines: bad_lines %d, first %d",
	      doc.bad_lines, doc.first_bad_line);

	CHECK(parse_text(dir, "unclosed",
		"x = 1\n"
		"keys = [\n"
		"  { mod=\"SUPER\", key=\"a\", func=\"view\" },\n"), "the cut-off file did not parse");
	CHECK(doc.unclosed_line == 2, "an array that never closes: unclosed_line %d, want 2",
	      doc.unclosed_line);

	CHECK(parse_text(dir, "well-formed",
		"# comment\n"
		"[a]\n"
		"x = 1   # trailing\n"
		"s = \"text # not a comment\"\n"
		"list = [\"a\", \"b\"]\n"
		"rules = [ { class = \"a\" , isfloating = 1 } ]\n"
		"keys = [\n"
		"\n"
		"  # a comment line\n"
		"  { key=\"a\", exec=[\"x\", \"y]\"] },  { key = \"b\" , n = 2 } ,\n"
		"]\n"), "the well-formed file did not parse");
	CHECK(doc.bad_lines == 0 && doc.long_arrays == 0 && !doc.unclosed_line,
	      "well-formed input reported problems: bad_lines %d (first %d), long_arrays %d, unclosed %d",
	      doc.bad_lines, doc.first_bad_line, doc.long_arrays, doc.unclosed_line);
}

#define CHECK_CLEAN(file) CHECK(!doc.bad_lines && !doc.long_arrays && !doc.unclosed_line, \
	"%s: bad_lines %d (first %d), long_arrays %d, unclosed %d", file, doc.bad_lines, \
	doc.first_bad_line, doc.long_arrays, doc.unclosed_line)

static void
shipped(const char *hotkeys, int keys, int tag_keys, int buttons,
        const char *rules_file, int rules, const char *themes)
{
	const TomlValue *v;
	char section[TOML_MAX_STR + 8];
	int i, n = 0;

	CHECK(toml_parse(hotkeys, &doc), "%s did not parse", hotkeys);
	CHECK_CLEAN(hotkeys);
	CHECK(toml_table_count(&doc, "keys") == keys, "hotkeys keys: %d, the file has %d",
	      toml_table_count(&doc, "keys"), keys);
	CHECK(toml_table_count(&doc, "tag_keys") == tag_keys, "hotkeys tag_keys: %d, the file has %d",
	      toml_table_count(&doc, "tag_keys"), tag_keys);
	CHECK(toml_table_count(&doc, "buttons") == buttons, "hotkeys buttons: %d, the file has %d",
	      toml_table_count(&doc, "buttons"), buttons);

	CHECK(toml_parse(rules_file, &doc), "%s did not parse", rules_file);
	CHECK_CLEAN(rules_file);
	CHECK(toml_table_count(&doc, "rules") == rules, "window rules: %d, the file has %d",
	      toml_table_count(&doc, "rules"), rules);
	for (i = 0; i < toml_table_count(&doc, "rules"); i++)
		CHECK(table_str("rules", i, "class") || table_str("rules", i, "instance")
		      || table_str("rules", i, "title"), "shipped rule %d matches every window", i);

	CHECK(toml_parse(themes, &doc), "%s did not parse", themes);
	CHECK_CLEAN(themes);
	v = toml_get(&doc, "active", "theme");
	CHECK(v && v->type == TOML_STRING && v->s[0], "themes.toml has no active theme");
	if (v && v->type == TOML_STRING) {
		snprintf(section, sizeof section, "theme.%s", v->s);
		for (i = 0; i < doc.n; i++)
			n += strcmp(doc.entries[i].section, section) == 0;
		CHECK(n > 0, "the active theme [%s] has no entries", section);
	}
}

int
main(int argc, char *argv[])
{
	if (argc != 9) {
		fprintf(stderr, "usage: %s WORKDIR HOTKEYS KEYS TAG_KEYS BUTTONS RULES_FILE RULES THEMES\n", argv[0]);
		return 2;
	}
	comment_brace(argv[1]);
	same_line_close(argv[1]);
	first_line_table(argv[1]);
	booleans(argv[1]);
	escaped_quote(argv[1]);
	long_string(argv[1]);
	long_line(argv[1]);
	regressions(argv[1]);
	truncation(argv[1]);
	problems(argv[1]);
	shipped(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6], atoi(argv[7]), argv[8]);
	if (failures) {
		fprintf(stderr, "tomlparser: %d check(s) failed\n", failures);
		return 1;
	}
	printf("tomlparser unit tests: PASS\n");
	return 0;
}
