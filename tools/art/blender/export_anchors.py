#!/usr/bin/env python3
"""Writes the attack anchors (weapon hand, other hand, spell focus, body
centre per facing) into the characters' *_anim.json files, from the same
models render_characters.py renders, without re-rendering the sheets.

Usage:  .venv-art/bin/python tools/art/blender/export_anchors.py [name ...]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import render_characters  # noqa: E402

if __name__ == "__main__":
    render_characters.export_anchors(sys.argv[1:] or None)
