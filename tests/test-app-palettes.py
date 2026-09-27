#!/usr/bin/env python3
"""Generated Qt palettes and GTK 2 themes: structure, and readable colours for every preset."""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GENERATOR = REPO / "scripts/lyona-gtk-theme"
THEMES = REPO / "config/themes.toml"

# QPalette roles in the order qt5ct/qt6ct read them.
ROLES = [
    "WindowText", "Button", "Light", "Midlight", "Dark", "Mid", "Text",
    "BrightText", "ButtonText", "Base", "Window", "Shadow", "Highlight",
    "HighlightedText", "Link", "LinkVisited", "AlternateBase", "NoRole",
    "ToolTipBase", "ToolTipText", "PlaceholderText",
]


def luminance(colour):
    channels = [int(colour[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    channels = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


class AppPaletteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        subprocess.run([str(GENERATOR), "generate-all", str(THEMES), cls.tmp.name], check=True)
        cls.themes = sorted(Path(cls.tmp.name).glob("Lyona-*"))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def scheme(self, theme):
        lines = (theme / "qt/colors.conf").read_text().splitlines()
        self.assertEqual(lines[0], "[ColorScheme]", theme.name)
        self.assertEqual(len(lines), 4, theme.name)
        result = {}
        for line in lines[1:]:
            key, value = line.split("=", 1)
            colours = [c.strip() for c in value.split(",")]
            self.assertEqual(len(colours), len(ROLES), f"{theme.name} {key}")
            for colour in colours:
                self.assertRegex(colour, r"^#ff[0-9A-Fa-f]{6}$", f"{theme.name} {key}")
            result[key] = ["#" + c[3:] for c in colours]
        self.assertEqual(sorted(result), ["active_colors", "disabled_colors", "inactive_colors"])
        return result

    def test_every_palette_has_a_qt_scheme_and_a_gtk2_theme(self):
        expected = len(re.findall(r"^\[theme\.", THEMES.read_text(), re.M))
        self.assertGreaterEqual(expected, 10)
        self.assertEqual(len(self.themes), expected)
        for theme in self.themes:
            self.scheme(theme)
            rc = (theme / "gtk-2.0/gtkrc").read_text()
            for state in ("NORMAL", "PRELIGHT", "ACTIVE", "SELECTED", "INSENSITIVE"):
                for name in ("bg", "base", "fg", "text"):
                    self.assertIn(f"{name}[{state}] =", rc, theme.name)
            self.assertIn('class "*" style "lyona-palette"', rc, theme.name)

    def test_qt_colours_are_readable_for_every_preset(self):
        for theme in self.themes:
            active = dict(zip(ROLES, self.scheme(theme)["active_colors"]))
            for text, background, minimum in (
                ("Text", "Base", 4.5),
                ("Text", "Window", 4.5),
                ("HighlightedText", "Highlight", 4.5),
                ("ToolTipText", "ToolTipBase", 4.5),
                # Placeholder text is meant to be dimmer than text; 3:1 is the floor.
                ("PlaceholderText", "Base", 3.0),
            ):
                ratio = contrast(active[text], active[background])
                self.assertGreaterEqual(
                    ratio, minimum, f"{theme.name}: {text} on {background} is {ratio:.2f}:1"
                )

    def test_window_and_base_follow_the_gtk_theme(self):
        # The same palette drives GTK and Qt, so an app in either toolkit matches.
        for theme in self.themes:
            css = (theme / "gtk-3.0/gtk.css").read_text()
            bg = re.search(r"@define-color lyona_bg\s+(#[0-9A-Fa-f]{6})", css).group(1)
            surface = re.search(r"@define-color lyona_surface\s+(#[0-9A-Fa-f]{6})", css).group(1)
            active = dict(zip(ROLES, self.scheme(theme)["active_colors"]))
            self.assertEqual(active["Window"].upper(), bg.upper(), theme.name)
            self.assertEqual(active["Base"].upper(), surface.upper(), theme.name)


if __name__ == "__main__":
    unittest.main()
