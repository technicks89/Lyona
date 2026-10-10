/* See LICENSE file for copyright and license details. */

#define MAX(A, B)               ((A) > (B) ? (A) : (B))
#define MIN(A, B)               ((A) < (B) ? (A) : (B))
#define BETWEEN(X, A, B)        ((A) <= (X) && (X) <= (B))
#define LENGTH(X)               (sizeof (X) / sizeof (X)[0])

void die(const char *fmt, ...);
void *ecalloc(size_t nmemb, size_t size);
/* Truncating strlcpy work-alike; always NUL-terminates when dstsz > 0. */
void copystr(char *dst, size_t dstsz, const char *src);
/* DIR/NAME into dst; 0 (and an empty dst) when it does not fit. */
int pathjoin(char *dst, size_t dstsz, const char *dir, const char *name);
/* The directory of /proc/self/exe: PREFIX/bin for an installed dwm. */
int exe_dir(char *out, size_t size);
