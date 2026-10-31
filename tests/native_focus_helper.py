#!/usr/bin/env python3
"""Own temporary X11 window for native application focus regression tests."""
from __future__ import annotations

import ctypes as c
from ctypes.util import find_library
from pathlib import Path
import sys
import time


def main() -> None:
    ready, release = map(Path, sys.argv[1:])
    x = c.CDLL(find_library("X11") or "libX11.so.6")
    display_t, window_t = c.c_void_p, c.c_ulong
    declarations = {
        "XOpenDisplay": ([c.c_char_p], display_t),
        "XDefaultRootWindow": ([display_t], window_t),
        "XGetInputFocus": ([display_t, c.POINTER(window_t), c.POINTER(c.c_int)], c.c_int),
        "XCreateSimpleWindow": ([display_t, window_t, c.c_int, c.c_int, c.c_uint, c.c_uint, c.c_uint, c.c_ulong, c.c_ulong], window_t),
        "XSelectInput": ([display_t, window_t, c.c_long], c.c_int),
        "XStoreName": ([display_t, window_t, c.c_char_p], c.c_int),
        "XMapRaised": ([display_t, window_t], c.c_int),
        "XSync": ([display_t, c.c_int], c.c_int),
        "XPending": ([display_t], c.c_int),
        "XNextEvent": ([display_t, c.c_void_p], c.c_int),
        "XSetInputFocus": ([display_t, window_t, c.c_int, c.c_ulong], c.c_int),
        "XDestroyWindow": ([display_t, window_t], c.c_int),
        "XCloseDisplay": ([display_t], c.c_int),
    }
    for name, (arguments, result) in declarations.items():
        function = getattr(x, name)
        function.argtypes, function.restype = arguments, result
    display = x.XOpenDisplay(None)
    if not display:
        raise RuntimeError("Native focus regression cannot open its X11 display")
    old_focus, old_revert = window_t(), c.c_int()
    x.XGetInputFocus(display, c.byref(old_focus), c.byref(old_revert))
    window = x.XCreateSimpleWindow(display, x.XDefaultRootWindow(display), 40, 40, 280, 100, 0, 0, 0x22363C)
    try:
        x.XSelectInput(display, window, 1 << 17)
        x.XStoreName(display, window, b"Outpost Exodus native focus test helper")
        x.XMapRaised(display, window)
        x.XSync(display, False)
        event = (c.c_long * 24)()
        mapped = False
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline and not mapped:
            while x.XPending(display):
                x.XNextEvent(display, c.byref(event))
                mapped |= c.cast(c.byref(event), c.POINTER(c.c_int))[0] == 19
            if not mapped:
                time.sleep(0.01)
        if not mapped:
            raise RuntimeError("Native focus helper was never mapped")
        x.XSetInputFocus(display, window, 2, 0)
        x.XSync(display, False)
        ready.write_text(str(window), encoding="ascii")
        deadline = time.monotonic() + 30.0
        while not release.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
    finally:
        x.XSetInputFocus(display, old_focus, old_revert, 0)
        x.XDestroyWindow(display, window)
        x.XSync(display, False)
        x.XCloseDisplay(display)


if __name__ == "__main__":
    main()
