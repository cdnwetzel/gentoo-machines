/* xidletime.c — Print X11 idle time in milliseconds
 *
 * Compile: gcc -o xidletime xidletime.c -lX11 -lXss
 * Install: sudo cp xidletime /usr/local/bin/
 * Requires: x11-libs/libXScrnSaver
 */

#include <stdio.h>
#include <X11/Xlib.h>
#include <X11/extensions/scrnsaver.h>

int main() {
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) return 1;
    XScreenSaverInfo *info = XScreenSaverAllocInfo();
    XScreenSaverQueryInfo(dpy, DefaultRootWindow(dpy), info);
    printf("%lu\n", info->idle);
    XFree(info);
    XCloseDisplay(dpy);
    return 0;
}
