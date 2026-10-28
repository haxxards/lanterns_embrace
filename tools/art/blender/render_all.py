#!/usr/bin/env python3
"""Renders the game's art with Blender (as a Python module).

Setup (once):  python3.13 -m venv .venv-art && .venv-art/bin/pip install bpy==5.2.2 numpy pillow
Usage:         .venv-art/bin/python tools/art/blender/render_all.py [terrain] [props] [characters] [items] [interiors] [ui]
               .venv-art/bin/python tools/art/blender/render_all.py terrain:grass props:tree_oak
               .venv-art/bin/python tools/art/blender/render_all.py --style painted items:longsword

Outputs overwrite the PNGs under assets/ (same paths, so they stay drop-in), and
prop origins/door pixels are written back into data/props/props.json.

Art styles: items come in two looks, "classic" (assets/items/) and "painted"
(assets/items/painted/, see docs/PAINTED_STYLE.md). Both are rendered unless
--style picks one; the game shows the one named in data/config/game_config.json.
Everything else has the classic look only.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import render_characters  # noqa: E402
import render_interiors  # noqa: E402
import render_items  # noqa: E402
import render_items_painted  # noqa: E402
import render_props  # noqa: E402
import render_terrain  # noqa: E402
import render_ui  # noqa: E402

# group -> {style: module}
GROUPS = {"terrain": {"classic": render_terrain}, "props": {"classic": render_props},
          "characters": {"classic": render_characters},
          "items": {"classic": render_items, "painted": render_items_painted},
          "interiors": {"classic": render_interiors}, "ui": {"classic": render_ui}}
STYLES = ("classic", "painted")


def main(argv):
    style = None
    targets = []
    args = iter(argv)
    for a in args:
        if a == "--style":
            style = next(args, None)
        elif a.startswith("--style="):
            style = a.split("=", 1)[1]
        else:
            targets.append(a)
    if style is not None and style not in STYLES:
        sys.exit(f"unknown style {style!r}: use one of {', '.join(STYLES)}")
    for t in targets or list(GROUPS):
        group, _, item = t.partition(":")
        for name, module in GROUPS[group].items():
            if style in (None, name):
                module.run([item] if item else None)
            elif len(GROUPS[group]) == 1:
                print(f"{group}: only the classic style exists, skipped")


if __name__ == "__main__":
    main(sys.argv[1:])
