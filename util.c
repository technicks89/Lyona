/* See LICENSE file for copyright and license details. */
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "util.h"

void
die(const char *fmt, ...)
{
	va_list ap;
	int saved_errno;

	saved_errno = errno;

	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);

	if (fmt[0] && fmt[strlen(fmt)-1] == ':')
		fprintf(stderr, " %s", strerror(saved_errno));
	fputc('\n', stderr);

	exit(1);
}

void *
ecalloc(size_t nmemb, size_t size)
{
	void *p;

	if (!(p = calloc(nmemb, size)))
		die("calloc:");
	return p;
}

void
copystr(char *dst, size_t dstsz, const char *src)
{
	size_t len;

	if (dstsz == 0)
		return;
	len = strlen(src);
	if (len >= dstsz)
		len = dstsz - 1;
	memcpy(dst, src, len);
	dst[len] = '\0';
}

int
pathjoin(char *dst, size_t dstsz, const char *dir, const char *name)
{
	size_t dirlen = strlen(dir);
	size_t namelen = strlen(name);

	if (dirlen >= dstsz || namelen >= dstsz - dirlen - 1) {
		if (dstsz > 0)
			dst[0] = '\0';
		return 0;
	}
	memcpy(dst, dir, dirlen);
	dst[dirlen] = '/';
	memcpy(dst + dirlen + 1, name, namelen + 1);
	return 1;
}

/* The directory dwm runs from: PREFIX/bin once installed. */
int
exe_dir(char *out, size_t size)
{
	char *slash;
	ssize_t n = readlink("/proc/self/exe", out, size);

	if (n <= 0 || (size_t)n >= size)
		return 0;
	out[n] = '\0';
	if (!(slash = strrchr(out, '/')))
		return 0;
	*slash = '\0';
	return 1;
}
