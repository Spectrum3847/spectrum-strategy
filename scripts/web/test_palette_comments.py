#!/usr/bin/env python3
"""Every StrategyPalette token named in web/ must match the palette.

Nothing under `web/` can read Dart: those files are parsed before any of it
runs, so a colour there has to be a literal. The convention is that each
literal names the token it mirrors in a comment, which is the only thread back
to the design system.

A comment that names the wrong token is worse than none: it reads as verified
and sends the next person to change the wrong constant. I got two of them wrong
by hand in one sitting, `darkError` and `darkOnPrimary`, which is why this
exists rather than another instruction to be careful.
"""

import re
import sys
import unittest
from pathlib import Path

PALETTE = Path("lib/src/theme/strategy_palette.dart")
WEB_FILES = ("web/index.html", "web/offline-check.html")

CLAIM = re.compile(r"#([0-9A-Fa-f]{6})'?[;,]?\s*/\*\s*StrategyPalette\.(\w+)")
DEFINITION = re.compile(
    r"static const Color (\w+) = Color\(0x[Ff][Ff]([0-9A-Fa-f]{6})\)"
)

def palette_values():
    return {
        name: value.lower()
        for name, value in DEFINITION.findall(PALETTE.read_text())
    }

def claims(path):
    return [
        (value.lower(), token) for value, token in CLAIM.findall(Path(path).read_text())
    ]

class PaletteCommentTest(unittest.TestCase):
    def test_every_named_token_exists_and_matches(self):
        palette = palette_values()
        self.assertTrue(palette, f"no colours parsed out of {PALETTE}")
        for path in WEB_FILES:
            for value, token in claims(path):
                with self.subTest(path=path, token=token):
                    self.assertIn(
                        token,
                        palette,
                        f"{path} names StrategyPalette.{token}, which does not exist",
                    )
                    self.assertEqual(
                        palette[token],
                        value,
                        f"{path} says #{value} is StrategyPalette.{token}, "
                        f"but that token is #{palette[token]}",
                    )

    def test_the_convention_is_actually_in_use(self):

        total = sum(len(claims(path)) for path in WEB_FILES)
        self.assertGreater(total, 0, "no palette comments found to check")

if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
