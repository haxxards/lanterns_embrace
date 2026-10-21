"""Painted-style experiment for character sprites, for review only: nothing
under assets/ changes.

Re-renders Garrick's fighter sprite with the materials and finishing pass in
painted.py, to see what the painted look does at sprite size. (The item icons
went on to use the style for real: render_items_painted.py.) Writes three
files: the plain render, the painted version at 4x, and the painted version at
game size. docs/PAINTED_STYLE.md, "Why only the icons", discusses the result.

    .venv-art/bin/python tools/art/blender/style_test.py OUT_DIR
"""
import sys
from pathlib import Path

import bpy
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))

import lib  # noqa: E402
import painted  # noqa: E402

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("style_test")


def _painted_for(name, color, rough=0.7, metallic=0.0, **_kw):
    """Stands in for render_characters.mat(): picks a painted material by name."""
    n = name.lower()
    hexc = "#%02x%02x%02x" % tuple(round(max(0, min(1, c)) ** (1 / 2.2) * 255) for c in color[:3]) \
        if not isinstance(color, str) else color
    if "mail" in n:
        return painted.chain(name, hexc, rings=110.0)
    if metallic >= 0.6 or any(k in n for k in ("steel", "brass", "gold", "iron")):
        return painted.gold(name) if any(k in n for k in ("brass", "gold")) else \
            painted.metal(name, painted._shade(hexc, 0.78))
    if any(k in n for k in ("wood", "haft", "staff", "bow")):
        return painted.wood(name, hexc, 8.0)
    if any(k in n for k in ("boot", "belt", "leather", "jerkin", "quiver", "glove")):
        return painted.leather(name, hexc)
    if "skin" in n:
        return painted.skin(name, hexc)
    if any(k in n for k in ("eye", "glint", "crystal", "flame")):
        return lib.material(name, lib.lin(hexc), rough=rough)
    return painted.cloth(name, hexc, weave=260.0)


def garrick():
    import render_characters as rc
    original = rc.mat
    rc.mat = lambda name, color, **kw: _painted_for(name, color, **kw)
    try:
        rc.build("fighter", 45, 0.0, 0.0)
        bpy.context.scene.cycles.samples = 96
        bpy.context.scene.view_settings.view_transform = 'AgX'
        bpy.context.scene.view_settings.look = 'AgX - Punchy'
        for light in bpy.data.lights:  # AgX is a little darker: lift the sun to match
            light.energy *= 1.6
        objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        lib.SUPERSAMPLE = 8
        _cam, res = lib.frame_oblique(objs, margin_px=4)
        raw = lib.render(OUT / "garrick_plain.png")
        art = painted.finish_painted(raw, radius=6, outline_px=5)
        art.resize((res[0] * 4, res[1] * 4), Image.LANCZOS).save(OUT / "garrick_painted.png")
        game = art.resize(res, Image.LANCZOS).filter(ImageFilter.UnsharpMask(0.8, 50, 2))
        game.save(OUT / "garrick_game.png")
    finally:
        rc.mat = original
        lib.SUPERSAMPLE = 2
    print("wrote garrick", res)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    garrick()
