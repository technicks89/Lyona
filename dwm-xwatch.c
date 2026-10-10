/* See LICENSE file for copyright and license details.
 *
 * dwm-xwatch: say which X properties changed, for dwm-quickshell-state's watch
 * (Sync Sprint 16 R16-40). One process watches the root window and every
 * managed client, where the state bridge used to keep one `xprop -spy` per
 * window, whose lines did not say which window they came from, so that every
 * change re-read every window. Needs only libX11, and is not part of the window
 * manager.
 *
 * It prints one line per change, and flushes after each burst:
 *   ready             once it is watching
 *   root PROPERTY     a root property the shell shows changed
 *   window 0xID       a client's title, class or tag changed
 *   clients           _NET_CLIENT_LIST changed (new clients are watched)
 *
 * It exits 0 when its output is closed, and 2 when it cannot open the display.
 */
#include <signal.h>
#include <stdio.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>

static const char *const rootprops[] = {
	"DWM_TAG_UPDATE", "_DWM_MONITOR_DESKTOPS", "_DWM_SELECTED_MONITOR", "_DWM_MONITOR_WINDOWS", "_DWM_LAYOUT",
	"_NET_CURRENT_DESKTOP", "_NET_NUMBER_OF_DESKTOPS", "_NET_DESKTOP_NAMES",
	"_NET_ACTIVE_WINDOW", "_DWM_FULLSCREEN_MONITORS", "WM_NAME",
};
#define NROOT (sizeof(rootprops) / sizeof(rootprops[0]))
/* _NET_WM_WINDOW_TYPE: a dock is left out of the state, so a window that
 * stops being one has to be read again. */
static const char *const clientprops[] = { "WM_NAME", "_NET_WM_NAME", "WM_CLASS", "_NET_WM_DESKTOP",
	"_NET_WM_WINDOW_TYPE" };
#define NCLIENT (sizeof(clientprops) / sizeof(clientprops[0]))

static Atom rootatoms[NROOT], clientatoms[NCLIENT], clientlist;

/* A client can be destroyed between the list naming it and the request that
 * watches it: that BadWindow is expected, and every other error is ignored too,
 * rather than ending the watch. */
static int
onxerror(Display *dpy, XErrorEvent *ee)
{
	(void)dpy;
	(void)ee;
	return 0;
}

static int
inlist(Atom atom, const Atom *atoms, size_t n)
{
	size_t i;

	for (i = 0; i < n; i++)
		if (atoms[i] == atom)
			return 1;
	return 0;
}

/* Watch every client _NET_CLIENT_LIST names. Selecting the same mask again on a
 * window already watched is harmless, and a window gone from the list stops
 * reporting on its own. */
static void
watchclients(Display *dpy, Window root)
{
	Atom type;
	int format;
	unsigned long n, after, i;
	unsigned char *data = NULL;

	if (XGetWindowProperty(dpy, root, clientlist, 0, 4096, False, XA_WINDOW, &type, &format,
	                       &n, &after, &data) != Success || !data)
		return;
	if (type == XA_WINDOW && format == 32)
		for (i = 0; i < n; i++)
			XSelectInput(dpy, ((Window *)data)[i], PropertyChangeMask);
	XFree(data);
}

int
main(void)
{
	Display *dpy;
	Window root;
	XEvent ev;
	size_t i;

	/* A closed reader makes the write fail, and the watch end. */
	signal(SIGPIPE, SIG_IGN);
	if (!(dpy = XOpenDisplay(NULL))) {
		fputs("dwm-xwatch: cannot open the display\n", stderr);
		return 2;
	}
	XSetErrorHandler(onxerror);
	root = DefaultRootWindow(dpy);
	for (i = 0; i < NROOT; i++)
		rootatoms[i] = XInternAtom(dpy, rootprops[i], False);
	for (i = 0; i < NCLIENT; i++)
		clientatoms[i] = XInternAtom(dpy, clientprops[i], False);
	clientlist = XInternAtom(dpy, "_NET_CLIENT_LIST", False);

	XSelectInput(dpy, root, PropertyChangeMask);
	watchclients(dpy, root);
	XSync(dpy, False);
	if (puts("ready") == EOF || fflush(stdout) == EOF)
		return 0;

	for (;;) {
		XNextEvent(dpy, &ev);
		if (ev.type == PropertyNotify) {
			XPropertyEvent *pe = &ev.xproperty;
			if (pe->window == root) {
				if (pe->atom == clientlist) {
					watchclients(dpy, root);
					if (puts("clients") == EOF)
						break;
				} else if (inlist(pe->atom, rootatoms, NROOT)) {
					for (i = 0; i < NROOT && rootatoms[i] != pe->atom; i++)
						;
					if (printf("root %s\n", rootprops[i]) < 0)
						break;
				}
			} else if (inlist(pe->atom, clientatoms, NCLIENT)) {
				if (printf("window 0x%lx\n", (unsigned long)pe->window) < 0)
					break;
			}
		}
		/* One flush per burst: the reader coalesces bursts anyway. */
		if (!XPending(dpy) && fflush(stdout) == EOF)
			break;
	}
	XCloseDisplay(dpy);
	return 0;
}
