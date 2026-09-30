/* Sync Sprint 12 S12-05: unit tests for tomlparser.c, the parser dwm uses for
 * hotkeys.toml, themes.toml and window-rules.toml.
 *
 *   test-tomlparser WORKDIR HOTKEYS KEYS TAG_KEYS BUTTONS RULES_FILE RULES THEMES
 *
 * WORKDIR receives the small files each case writes. The remaining arguments are
 * the shipped files and the number of tables tests/test-tomlparser.sh counted in
 * each array, which the parser must reproduce exactly. */
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

	off += (size_t)snprintf(text + off, sizeof text - off, "[a]\n");
	for (i = 0; i < TOML_MAX_ENTRIES + 10; i++)
		off += (size_t)snprintf(text + off, sizeof text - off, "k%d = %d\n", i, i);
	CHECK(parse_text(dir, "long", text), "a long file did not parse");
	CHECK(doc.n == TOML_MAX_ENTRIES, "kept %d entries, not %d", doc.n, TOML_MAX_ENTRIES);
	CHECK(doc.truncated, "dropped entries were not recorded");

	off = 0;
	off += (size_t)snprintf(text + off, sizeof text - off, "keys = [\n");
	for (i = 0; i < TOML_MAX_ENTRIES / 2 + 10; i++)
		off += (size_t)snprintf(text + off, sizeof text - off, "  { a=\"x\", b=%d },\n", i);
	snprintf(text + off, sizeof text - off, "]\n");
	CHECK(parse_text(dir, "long-tables", text), "a long table array did not parse");
	CHECK(doc.truncated, "entries dropped from inline tables were not recorded");

	CHECK(parse_text(dir, "small-again", "[a]\nx = 1\n") && !doc.truncated,
	      "the flag survived into the next parse");
}

static void
shipped(const char *hotkeys, int keys, int tag_keys, int buttons,
        const char *rules_file, int rules, const char *themes)
{
	const TomlValue *v;
	char section[TOML_MAX_STR + 8];
	int i, n = 0;

	CHECK(toml_parse(hotkeys, &doc), "%s did not parse", hotkeys);
	CHECK(toml_table_count(&doc, "keys") == keys, "hotkeys keys: %d, the file has %d",
	      toml_table_count(&doc, "keys"), keys);
	CHECK(toml_table_count(&doc, "tag_keys") == tag_keys, "hotkeys tag_keys: %d, the file has %d",
	      toml_table_count(&doc, "tag_keys"), tag_keys);
	CHECK(toml_table_count(&doc, "buttons") == buttons, "hotkeys buttons: %d, the file has %d",
	      toml_table_count(&doc, "buttons"), buttons);

	CHECK(toml_parse(rules_file, &doc), "%s did not parse", rules_file);
	CHECK(toml_table_count(&doc, "rules") == rules, "window rules: %d, the file has %d",
	      toml_table_count(&doc, "rules"), rules);
	for (i = 0; i < toml_table_count(&doc, "rules"); i++)
		CHECK(table_str("rules", i, "class") || table_str("rules", i, "instance")
		      || table_str("rules", i, "title"), "shipped rule %d matches every window", i);

	CHECK(toml_parse(themes, &doc), "%s did not parse", themes);
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
	regressions(argv[1]);
	truncation(argv[1]);
	shipped(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6], atoi(argv[7]), argv[8]);
	if (failures) {
		fprintf(stderr, "tomlparser: %d check(s) failed\n", failures);
		return 1;
	}
	printf("tomlparser unit tests: PASS\n");
	return 0;
}
