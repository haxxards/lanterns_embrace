#!/usr/bin/env python3
"""Renders the game's art with Blender (as a Python module).

Setup (once):  python3.13 -m venv .venv-art && .venv-art/bin/pip install bpy==5.2.2 numpy pillow
Usage:         .venv-art/bin/python tools/art/blender/render_all.py [terrain] [props] [characters]
               .venv-art/bin/python tools/art/blender/render_all.py terrain:grass props:tree_oak

Outputs overwrite the PNGs under assets/ (same paths, so they stay drop-in), and
prop origins/door pixels are written back into data/props/props.json.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import render_characters  # noqa: E402
import render_props  # noqa: E402
import render_terrain  # noqa: E402

GROUPS = {"terrain": render_terrain, "props": render_props, "characters": render_characters}


def main(argv):
    targets = argv or list(GROUPS)
    for t in targets:
        group, _, item = t.partition(":")
        module = GROUPS[group]
        module.run([item] if item else None)


if __name__ == "__main__":
    main(sys.argv[1:])
