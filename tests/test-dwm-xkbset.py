#!/usr/bin/python3
"""dwm-xkbset against a real X server: controls toggle alone and persist."""

import ctypes as c
import importlib.machinery
import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / "scripts/dwm-xkbset"
HEADER = Path("/usr/include/X11/extensions/XKB.h")
LABELS = {
    "a": "Accessibility Features (AccessX)",
    "st": "Sticky-Keys",
    "sl": "Slow-Keys",
    "bo": "Bounce-Keys",
    "m": "Mouse-Keys",
}


def helper(*arguments, env=None):
    return subprocess.run(
        [str(HELPER), *arguments],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )


def state():
    result = helper("q")
    assert result.returncode == 0, result.stderr
    found = {}
    for line in result.stdout.splitlines():
        label, _, value = line.partition(" = ")
        assert value in ("On", "Off"), f"unexpected query line: {line!r}"
        found[label] = value == "On"
    assert list(found) == list(LABELS.values()), f"unexpected labels: {list(found)}"
    return found


def only(option):
    return {label: label == LABELS[option] for label in LABELS.values()}


def load_helper_module():
    loader = importlib.machinery.SourceFileLoader("dwm_xkbset", str(HELPER))
    spec = importlib.util.spec_from_loader("dwm_xkbset", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def check_constants_against_header():
    """The masks are copied by hand, so compare them with the real header."""
    if not HEADER.exists():
        print("XKB.h not installed; skipping the constants cross-check")
        return
    module = load_helper_module()
    text = HEADER.read_text()
    for name, value in {
        "XkbSlowKeysMask": module.XKB_SLOW_KEYS,
        "XkbBounceKeysMask": module.XKB_BOUNCE_KEYS,
        "XkbStickyKeysMask": module.XKB_STICKY_KEYS,
        "XkbMouseKeysMask": module.XKB_MOUSE_KEYS,
        "XkbAccessXKeysMask": module.XKB_ACCESSX_KEYS,
        "XkbAllControlsMask": module.XKB_ALL_CONTROLS_MASK,
        "XkbUseCoreKbd": module.XKB_USE_CORE_KBD,
    }.items():
        match = re.search(rf"#define\s+{name}\s+\(?(.+?)\)?\s*(?:/\*.*)?$", text, re.M)
        assert match, f"{name} is not defined in {HEADER}"
        expected = eval(match.group(1).replace("L", ""), {"__builtins__": {}})  # noqa: S307
        assert value == expected, f"{name}: helper has {value:#x}, header has {expected:#x}"


def main():
    assert os.environ.get("DISPLAY"), "run under xvfb-run"
    check_constants_against_header()

    # A real session always has clients connected. Without one the X server
    # resets when the helper exits, and every control it changed reverts.
    x11 = c.CDLL("libX11.so.6")
    x11.XOpenDisplay.restype, x11.XOpenDisplay.argtypes = c.c_void_p, [c.c_char_p]
    holder = x11.XOpenDisplay(None)
    assert holder, "cannot open a holding X connection"

    baseline = state()
    try:
        for option in LABELS:
            helper(*(f"-{other}" for other in LABELS))
            assert not any(state().values()), "every control should start off"

            assert helper(option).returncode == 0
            assert state() == only(option), f"{option} did not enable exactly its control"

            assert helper(f"-{option}").returncode == 0
            assert not any(state().values()), f"-{option} did not turn its control off"

        # Options apply in order, and `q` in the same call reports the result.
        combined = helper("st", "sl", "-st", "q")
        assert combined.returncode == 0
        lines = dict(line.split(" = ") for line in combined.stdout.splitlines())
        assert lines[LABELS["sl"]] == "On" and lines[LABELS["st"]] == "Off", combined.stdout
        assert state()[LABELS["sl"]] and not state()[LABELS["st"]]
        helper("-sl")
        assert helper("st", "-st", "q").stdout.count("= On") == 0
        assert helper("-st", "st", "q").stdout.count("= On") == 1
        helper("-st")

        # Bad input is refused without touching any control.
        before = state()
        refused = helper("nosuch")
        assert refused.returncode == 2 and "unknown option: nosuch" in refused.stderr
        assert helper("--st").returncode == 2
        assert helper().returncode == 2
        assert state() == before, "a refused option changed a control"
        assert helper("--help").returncode == 0

        # Without a display the failure is a clear message, not a traceback.
        env = {key: value for key, value in os.environ.items() if key != "DISPLAY"}
        headless = helper("q", env=env)
        assert headless.returncode == 1, headless
        assert "cannot open DISPLAY" in headless.stderr and "Traceback" not in headless.stderr
    finally:
        for option, label in LABELS.items():
            helper(option if baseline[label] else f"-{option}")
        x11.XCloseDisplay.argtypes = [c.c_void_p]
        x11.XCloseDisplay(holder)
    print("dwm-xkbset: PASS")


if __name__ == "__main__":
    sys.exit(main())
