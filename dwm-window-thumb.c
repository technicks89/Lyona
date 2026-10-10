/* See LICENSE file for copyright and license details.
 *
 * dwm-window-thumb: capture a small preview of one X11 window for the window
 * overview (Sync Sprint 9 S9-01, docs/evidence/s9-01-thumbnail-spike.md).
 * Needs libX11 and libXrender, and is not part of the window manager.
 *
 * The X server scales the window down (XRender, halved step by step, so every
 * source pixel counts), and one small image of the result is read: at most
 * 160 KB for any window, where every row of it used to be fetched, 33 MB for a
 * 4K window (#323). Without Render, or if it fails, the window is fetched in bands and
 * scaled here, as before; LYONA_THUMB_NO_RENDER=1 forces that, for the tests.
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
#include <X11/extensions/Xrender.h>
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
/* Each XGetImage fetches a band of rows of at most this many bytes: a few round
 * trips per window rather than one per sampled row (up to 640), while a 4K
 * window is still never held whole in memory (Sync Sprint 16 R16-41). */
#define BAND_BYTES (4L << 20)

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

/* One Render step: SRC (SW x SH) scaled into a new RGB24 picture of DW x DH,
 * bilinear. At most 2x down per axis, bilinear samples exactly between pixels,
 * so each step is a 2x2 average on pixman's fast path. Returns the picture and
 * its pixmap in *PIX, or None. */
static Picture
halfstep(Display *dpy, Window root, XRenderPictFormat *fmt, Picture src,
         int sw, int sh, int dw, int dh, Pixmap *pix)
{
	XTransform xf;
	Picture dst;

	memset(&xf, 0, sizeof xf);
	xf.matrix[0][0] = XDoubleToFixed((double)sw / dw);
	xf.matrix[1][1] = XDoubleToFixed((double)sh / dh);
	xf.matrix[2][2] = XDoubleToFixed(1);
	*pix = XCreatePixmap(dpy, root, (unsigned)dw, (unsigned)dh, 24);
	dst = XRenderCreatePicture(dpy, *pix, fmt, 0, NULL);
	XRenderSetPictureTransform(dpy, src, &xf);
	XRenderSetPictureFilter(dpy, src, FilterBilinear, NULL, 0);
	XRenderComposite(dpy, PictOpSrc, src, None, dst, 0, 0, 0, 0, 0, 0,
	                 (unsigned)dw, (unsigned)dh);
	return dst;
}

/* WIN scaled to DW x DH by the X server (#323): halved with Render until it is
 * within twice the preview on each side, then one last bilinear step, and the
 * result read with one XGetImage. Each halving averages 2x2 pixels, so every
 * source pixel counts, as a box filter would, at a fraction of a convolution's
 * cost in the server (a 15x15 convolution took 43 ms for a 4K window, and the
 * server serves no one meanwhile). Fills OUT (DW x DH, RGB) and returns 1; 0
 * when Render is missing or fails, for the client-side path. */
static int
serverscale(Display *dpy, Window win, const XWindowAttributes *wa, int dw, int dh,
            unsigned char *out)
{
	XRenderPictFormat *srcfmt, *fmt;
	XRenderPictureAttributes pa;
	Picture cur, next;
	Pixmap curpix = None, nextpix;
	XImage *img;
	int ev, er, cw = wa->width, ch = wa->height, nw, nh, x, y, ok = 0;
	unsigned long p;

	if (getenv("LYONA_THUMB_NO_RENDER") || !XRenderQueryExtension(dpy, &ev, &er)
	    || !(srcfmt = XRenderFindVisualFormat(dpy, wa->visual))
	    || !(fmt = XRenderFindStandardFormat(dpy, PictStandardRGB24)))
		return 0;
	memset(&pa, 0, sizeof pa);
	pa.subwindow_mode = IncludeInferiors;
	cur = XRenderCreatePicture(dpy, win, srcfmt, CPSubwindowMode, &pa);
	while (cw > dw || ch > dh) {
		nw = cw > 2 * dw ? (cw + 1) / 2 : dw;
		nh = ch > 2 * dh ? (ch + 1) / 2 : dh;
		next = halfstep(dpy, wa->root, fmt, cur, cw, ch, nw, nh, &nextpix);
		XRenderFreePicture(dpy, cur);
		if (curpix != None)
			XFreePixmap(dpy, curpix);
		cur = next, curpix = nextpix, cw = nw, ch = nh;
	}
	if (curpix == None) {
		/* Already preview-sized: nothing to scale, the client-side path
		 * reads it as it is, without an error from the picture above. */
		XRenderFreePicture(dpy, cur);
		XSync(dpy, False);
		x_error = 0;
		return 0;
	}
	/* Its reply comes after any error the requests above caused. */
	img = XGetImage(dpy, curpix, 0, 0, (unsigned)dw, (unsigned)dh, AllPlanes, ZPixmap);
	if (img && !x_error) {
		/* The pixmap's layout is the RGB24 picture format's, not a visual's. */
		for (y = 0; y < dh; y++)
			for (x = 0; x < dw; x++) {
				p = XGetPixel(img, x, y);
				out[((size_t)y * dw + x) * 3] = (unsigned char)((p >> fmt->direct.red) & fmt->direct.redMask);
				out[((size_t)y * dw + x) * 3 + 1] = (unsigned char)((p >> fmt->direct.green) & fmt->direct.greenMask);
				out[((size_t)y * dw + x) * 3 + 2] = (unsigned char)((p >> fmt->direct.blue) & fmt->direct.blueMask);
			}
		ok = 1;
	}
	if (img)
		XDestroyImage(img);
	if (cur != None)
		XRenderFreePicture(dpy, cur);
	if (curpix != None)
		XFreePixmap(dpy, curpix);
	XSync(dpy, False);
	x_error = 0; /* a failure here leaves the client-side path to try */
	return ok;
}

static int
capture(Display *dpy, Window win)
{
	XWindowAttributes wa;
	XImage *band;
	unsigned char *out = NULL;
	unsigned long *sum = NULL, *cnt = NULL;
	int dfd = -1, ofd = -1, status = EXIT_FAIL;
	int dw, dh, dx, dy, dend, y, i, j, nx, ny, x0, x1, y0, y1, rs, gs, bs, hdr;
	int bandtop, bandend;
	long maxrows;
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
	if (serverscale(dpy, win, &wa, dw, dh, out))
		goto write;

	/* The source rows output row K samples from: [SRCY0(K), SRCY1(K)). */
#define SRCY0(k) ((int)((long)(k) * wa.height / dh))
#define SRCY1(k) (SRCY0((k) + 1) > SRCY0(k) ? SRCY0((k) + 1) : SRCY0(k) + 1)
	maxrows = BAND_BYTES / ((long)wa.width * 4);
	if (maxrows < 1)
		maxrows = 1;
	for (dy = 0; dy < dh; ) {
		/* The output rows whose source rows fit in one band (at least one). */
		bandtop = SRCY0(dy);
		for (dend = dy + 1; dend < dh && SRCY1(dend) - bandtop <= maxrows; dend++)
			;
		bandend = SRCY1(dend - 1);
		if (bandend > wa.height)
			bandend = wa.height;
		/* XGetImage waits for its reply, and an error for it reaches
		 * onxerror before it returns: no XSync (a second round trip). */
		band = XGetImage(dpy, win, 0, bandtop, wa.width, bandend - bandtop, AllPlanes, ZPixmap);
		if (!band || x_error) {
			if (band)
				XDestroyImage(band);
			goto done;
		}
		rs = maskshift(band->red_mask);
		gs = maskshift(band->green_mask);
		bs = maskshift(band->blue_mask);
		for (; dy < dend; dy++) {
			y0 = SRCY0(dy);
			y1 = SRCY1(dy);
			if (y1 > bandend)
				y1 = bandend;
			ny = y1 - y0 < SAMPLES ? y1 - y0 : SAMPLES;
			memset(sum, 0, sizeof(unsigned long) * dw * 3);
			memset(cnt, 0, sizeof(unsigned long) * dw);
			for (j = 0; j < ny; j++) {
				y = y0 + (j * (y1 - y0)) / ny - bandtop;
				for (dx = 0; dx < dw; dx++) {
					x0 = (int)((long)dx * wa.width / dw);
					x1 = (int)((long)(dx + 1) * wa.width / dw);
					if (x1 <= x0)
						x1 = x0 + 1;
					nx = x1 - x0 < SAMPLES ? x1 - x0 : SAMPLES;
					for (i = 0; i < nx; i++) {
						unsigned long p = XGetPixel(band, x0 + (i * (x1 - x0)) / nx, y);
						sum[dx * 3] += (p & band->red_mask) >> rs;
						sum[dx * 3 + 1] += (p & band->green_mask) >> gs;
						sum[dx * 3 + 2] += (p & band->blue_mask) >> bs;
						cnt[dx]++;
					}
				}
			}
			for (dx = 0; dx < dw; dx++)
				for (i = 0; i < 3; i++)
					out[((size_t)dy * dw + dx) * 3 + i] = (unsigned char)(sum[dx * 3 + i] / cnt[dx]);
		}
		XDestroyImage(band);
	}
#undef SRCY0
#undef SRCY1

write:
	if ((dfd = opendirsafe(1)) < 0)
		goto done;
	snprintf(tmp, sizeof tmp, ".tmp-%ld", (long)getpid());
	snprintf(name, sizeof name, "%lx.ppm", (unsigned long)win);
	if (unlinkat(dfd, tmp, 0) < 0 && errno != ENOENT)
		goto done;
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
