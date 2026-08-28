/* See LICENSE file for copyright and license details. */

#define MAX(A, B)               ((A) > (B) ? (A) : (B))
#define MIN(A, B)               ((A) < (B) ? (A) : (B))
#define BETWEEN(X, A, B)        ((A) <= (X) && (X) <= (B))
#define LENGTH(X)               (sizeof (X) / sizeof (X)[0])

void die(const char *fmt, ...);
void *ecalloc(size_t nmemb, size_t size);
/* Truncating strlcpy work-alike; always NUL-terminates when dstsz > 0. */
void copystr(char *dst, size_t dstsz, const char *src);
