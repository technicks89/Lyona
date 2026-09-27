/* See LICENSE file for copyright and license details.
 *
 * dwm-window-thumb: capture a small preview of one X11 window for the window
 * overview (Sync Sprint 9 S9-01, docs/evidence/s9-01-thumbnail-spike.md).
 * Needs only libX11, and is not part of the window manager.
 *
 *   dwm-window-thumb available        exit 0 if previews can be captured
 *   dwm-window-thumb capture WINDOW   write the preview, print its path
 *   dwm-window-thumb purge            delete every stored preview
 *
 * A window on another tag is mapped but moved off screen, and only a
 * compositor keeps its pixels, so nothing is captured unless one is running
 * (a compositor owns the _NET_WM_CM_S<screen> selection). Without one an
 * off-screen window cannot be read at all, and a window that is on screen may
 * be covered by another. The overview then keeps its icon-and-title cards.
 *
 * The preview is the contents of a window the user may have put out of sight, so
 * it is only ever written to a private directory under $XDG_RUNTIME_DIR
 * (memory-backed, deleted at logout; there is deliberately no fallback to /tmp)
 * with mode 0600, and the overview purges it as soon as it closes. WINDOW is
 * the only argument that names anything: the output path is fixed.
 *
 * Previews can be switched off with the word "off" in
 * ${XDG_CONFIG_HOME:-$HOME/.config}/lyona/overview-thumbnails.
 *
 * Exit status: 0 success, 2 bad usage or environment, 3 no compositor, 4
 * switched off, 5 window cannot be captured, 6 capture or write failed.
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define THUMB_MAX_W 256
#define THUMB_MAX_H 160
#define SAMPLES 4 /* source pixels sampled per axis for each preview pixel */

enum { EXIT_USAGE = 2, EXIT_NOCOMP = 3, EXIT_OFF = 4, EXIT_GONE = 5, EXIT_FAIL = 6 };

static int x_error;

static int
onxerror(Display *dpy, XErrorEvent *ee)
{
	(void)dpy;
	(void)ee;
	x_error = 1;
	return 0;
}

/* Number of low zero bits of a colour mask, to shift a channel down to 0..max. */
static int
maskshift(unsigned long mask)
{
	int n = 0;

	while (mask && !(mask & 1)) {
		mask >>= 1;
		n++;
	}
	return n;
}

static int
disabled(void)
{
	const char *base = getenv("XDG_CONFIG_HOME"), *home = getenv("HOME");
	char path[PATH_MAX], word[16];
	FILE *f;
	size_t n;
	int len, off;

	if (base && base[0] == '/')
		len = snprintf(path, sizeof path, "%s/lyona/overview-thumbnails", base);
	else if (home && home[0] == '/')
		len = snprintf(path, sizeof path, "%s/.config/lyona/overview-thumbnails", home);
	else
		return 0;
	if (len < 0 || (size_t)len >= sizeof path || !(f = fopen(path, "r")))
		return 0;
	n = fread(word, 1, sizeof word - 1, f);
	fclose(f);
	word[n] = '\0';
	while (n && (word[n - 1] == '\n' || word[n - 1] == ' ' || word[n - 1] == '\t'))
		word[--n] = '\0';
	off = !strcmp(word, "off") || !strcmp(word, "disabled");
	return off;
}

static int
havecompositor(Display *dpy)
{
	char name[32];
	Atom sel;

	snprintf(name, sizeof name, "_NET_WM_CM_S%d", DefaultScreen(dpy));
	sel = XInternAtom(dpy, name, True);
	return sel != None && XGetSelectionOwner(dpy, sel) != None;
}

/* Open $XDG_RUNTIME_DIR/lyona/overview-thumbs (creating it 0700 when asked to)
 * and return a descriptor for it, or -1. Refuses a directory that is not the
 * user's own or is open to anyone else: a directory someone else controls would
 * let them read or replace the previews. */
static int
opendirsafe(int create)
{
	static const char *const parts[] = { "lyona", "overview-thumbs" };
	const char *runtime = getenv("XDG_RUNTIME_DIR");
	int fd, next, i;
	struct stat st;

	if (!runtime || runtime[0] != '/')
		return -1;
	if ((fd = open(runtime, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)) < 0)
		return -1;
	for (i = 0; i < 2; i++) {
		if (create && mkdirat(fd, parts[i], 0700) < 0 && errno != EEXIST)
			goto fail;
		if ((next = openat(fd, parts[i], O_RDONLY | O_DIRECTORY | O_NOFOLLOW)) < 0)
			goto fail;
		close(fd);
		fd = next;
		if (fstat(fd, &st) < 0 || st.st_uid != geteuid() || (st.st_mode & 077))
			goto fail;
	}
	return fd;
fail:
	close(fd);
	return -1;
}

static int
parsewindow(const char *s, Window *win)
{
	char *end;
	unsigned long v;

	if (!s || !*s || *s == '-' || *s == '+' || isspace((unsigned char)*s))
		return 0;
	errno = 0;
	v = strtoul(s, &end, 0);
	if (errno || *end || v == 0 || v > 0xffffffffUL)
		return 0;
	*win = (Window)v;
	return 1;
}

static int
purge(void)
{
	struct dirent *de;
	DIR *dir;
	int fd;

	if ((fd = opendirsafe(0)) < 0)
		return 0; /* nothing stored, or nothing safe to touch */
	if (!(dir = fdopendir(fd))) {
		close(fd);
		return EXIT_FAIL;
	}
	while ((de = readdir(dir)))
		if (strcmp(de->d_name, ".") && strcmp(de->d_name, ".."))
			unlinkat(fd, de->d_name, 0);
	closedir(dir);
	return 0;
}

static int
capture(Display *dpy, Window win)
{
	XWindowAttributes wa;
	XImage *row;
	unsigned char *out = NULL;
	unsigned long *sum = NULL, *cnt = NULL;
	int dfd = -1, ofd = -1, status = EXIT_FAIL;
	int dw, dh, dx, dy, y, i, j, nx, ny, x0, x1, y0, y1, rs, gs, bs, hdr;
	char tmp[64], name[32], header[32];
	FILE *f = NULL;

	XSetErrorHandler(onxerror);
	if (!XGetWindowAttributes(dpy, win, &wa) || x_error || wa.map_state != IsViewable
	    || wa.class != InputOutput || wa.width <= 0 || wa.height <= 0
	    || wa.visual->class != TrueColor)
		return EXIT_GONE;

	dw = wa.width, dh = wa.height;
	if (dw > THUMB_MAX_W || dh > THUMB_MAX_H) { /* fit inside the box, never enlarge */
		if ((long)dw * THUMB_MAX_H > (long)dh * THUMB_MAX_W) {
			dh = (int)((long)dh * THUMB_MAX_W / dw);
			dw = THUMB_MAX_W;
		} else {
			dw = (int)((long)dw * THUMB_MAX_H / dh);
			dh = THUMB_MAX_H;
		}
		if (dw < 1)
			dw = 1;
		if (dh < 1)
			dh = 1;
	}
	if (!(out = malloc((size_t)dw * dh * 3)) || !(sum = malloc(sizeof(unsigned long) * dw * 3))
	    || !(cnt = malloc(sizeof(unsigned long) * dw)))
		goto done;

	for (dy = 0; dy < dh; dy++) {
		y0 = (int)((long)dy * wa.height / dh);
		y1 = (int)((long)(dy + 1) * wa.height / dh);
		if (y1 <= y0)
			y1 = y0 + 1;
		ny = y1 - y0 < SAMPLES ? y1 - y0 : SAMPLES;
		memset(sum, 0, sizeof(unsigned long) * dw * 3);
		memset(cnt, 0, sizeof(unsigned long) * dw);
		for (j = 0; j < ny; j++) {
			/* One row at a time, so a 4K window is never held whole in memory. */
			y = y0 + (j * (y1 - y0)) / ny;
			row = XGetImage(dpy, win, 0, y, wa.width, 1, AllPlanes, ZPixmap);
			XSync(dpy, False);
			if (!row || x_error) {
				if (row)
					XDestroyImage(row);
				goto done;
			}
			rs = maskshift(row->red_mask);
			gs = maskshift(row->green_mask);
			bs = maskshift(row->blue_mask);
			for (dx = 0; dx < dw; dx++) {
				x0 = (int)((long)dx * wa.width / dw);
				x1 = (int)((long)(dx + 1) * wa.width / dw);
				if (x1 <= x0)
					x1 = x0 + 1;
				nx = x1 - x0 < SAMPLES ? x1 - x0 : SAMPLES;
				for (i = 0; i < nx; i++) {
					unsigned long p = XGetPixel(row, x0 + (i * (x1 - x0)) / nx, 0);
					sum[dx * 3] += (p & row->red_mask) >> rs;
					sum[dx * 3 + 1] += (p & row->green_mask) >> gs;
					sum[dx * 3 + 2] += (p & row->blue_mask) >> bs;
					cnt[dx]++;
				}
			}
			XDestroyImage(row);
		}
		for (dx = 0; dx < dw; dx++)
			for (i = 0; i < 3; i++)
				out[((size_t)dy * dw + dx) * 3 + i] = (unsigned char)(sum[dx * 3 + i] / cnt[dx]);
	}

	if ((dfd = opendirsafe(1)) < 0)
		goto done;
	snprintf(tmp, sizeof tmp, ".tmp-%ld", (long)getpid());
	snprintf(name, sizeof name, "%lx.ppm", (unsigned long)win);
	if ((ofd = openat(dfd, tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600)) < 0)
		goto done;
	if (!(f = fdopen(ofd, "wb")))
		goto done;
	ofd = -1;
	hdr = snprintf(header, sizeof header, "P6\n%d %d\n255\n", dw, dh);
	if (fwrite(header, 1, (size_t)hdr, f) != (size_t)hdr
	    || fwrite(out, 1, (size_t)dw * dh * 3, f) != (size_t)dw * dh * 3 || fclose(f) != 0) {
		f = NULL;
		unlinkat(dfd, tmp, 0);
		goto done;
	}
	f = NULL;
	if (renameat(dfd, tmp, dfd, name) < 0) {
		unlinkat(dfd, tmp, 0);
		goto done;
	}
	printf("%s/lyona/overview-thumbs/%s\n", getenv("XDG_RUNTIME_DIR"), name);
	status = 0;
done:
	if (f)
		fclose(f);
	if (ofd >= 0)
		close(ofd);
	if (dfd >= 0)
		close(dfd);
	free(out);
	free(sum);
	free(cnt);
	return status;
}

int
main(int argc, char *argv[])
{
	Display *dpy;
	Window win = None;
	int status;

	if (argc == 2 && !strcmp(argv[1], "purge"))
		return purge();
	if (!((argc == 2 && !strcmp(argv[1], "available"))
	      || (argc == 3 && !strcmp(argv[1], "capture")))) {
		fputs("usage: dwm-window-thumb available | capture WINDOW | purge\n", stderr);
		return EXIT_USAGE;
	}
	if (argc == 3 && !parsewindow(argv[2], &win)) {
		fputs("dwm-window-thumb: WINDOW must be a window id\n", stderr);
		return EXIT_USAGE;
	}
	if (disabled())
		return EXIT_OFF;
	if (!(dpy = XOpenDisplay(NULL))) {
		fputs("dwm-window-thumb: cannot open display\n", stderr);
		return EXIT_USAGE;
	}
	if (!havecompositor(dpy))
		status = EXIT_NOCOMP;
	else if (argc == 2)
		status = 0;
	else
		status = capture(dpy, win);
	XCloseDisplay(dpy);
	return status;
}
