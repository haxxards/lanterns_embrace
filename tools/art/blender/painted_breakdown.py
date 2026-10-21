"""Pictures for docs/PAINTED_STYLE.md: one icon taken through the painted
recipe a step at a time, plus a strip showing how the two view transforms
(Standard and AgX) handle bright light.

    .venv-art/bin/python tools/art/blender/painted_breakdown.py            # shield
    .venv-art/bin/python tools/art/blender/painted_breakdown.py longsword

Writes docs/images/painted_style/<item>_NN_<stage>.png (256 px each),
<item>_brush_closeup.png, <item>_brush_radius.png and tone_curves.png.
Nothing in assets/ changes.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import lib  # noqa: E402
import painted  # noqa: E402
import render_items as ri  # noqa: E402
import render_items_painted as rp  # noqa: E402

OUT = lib.ROOT / "docs" / "images" / "painted_style"
TMP = Path(bpy.app.tempdir or "/tmp")
SHOW = 256
BG = (28, 24, 20)


def on_dark(img, size=SHOW, resample=Image.LANCZOS):
    """Puts an RGBA image on the inventory's dark background, at `size` px."""
    bg = Image.new("RGBA", img.size, (*BG, 255))
    bg.alpha_composite(img.convert("RGBA"))
    return bg.convert("RGB").resize((size, size), resample)


def render_stage(name, preview, view='AgX'):
    """Builds the model with painted.PREVIEW = preview and renders it."""
    painted.PREVIEW = preview
    try:
        elevation = rp.build(name)
    finally:
        painted.PREVIEW = None
    vs = bpy.context.scene.view_settings
    if preview in ("cavity", "edges") or view == 'Standard':
        vs.view_transform, vs.look = 'Standard', 'None'
    ri.RENDER = rp.RENDER
    ri.frame(elevation, margin=0.08)
    return lib.render(TMP / f"{name}_{preview}.png")


def breakdown(name):
    OUT.mkdir(parents=True, exist_ok=True)
    stages = []
    stages.append(("classic", on_dark(Image.open(lib.ASSETS / "items" / f"{name}.png"), resample=Image.NEAREST)))
    for preview in ("flat", "variation", "cavity", "grime", "edges"):
        stages.append((preview, on_dark(render_stage(name, preview))))
    raw = render_stage(name, None)
    stages.append(("material", on_dark(raw)))
    stages.append(("standard_view", on_dark(render_stage(name, None, view='Standard'))))
    brush = painted.finish_painted(raw, radius=5, outline_px=0, saturation=1.0, contrast=1.0)
    stages.append(("brushwork", on_dark(brush)))
    final = painted.finish_painted(raw, radius=5, outline_px=4)
    stages.append(("outline", on_dark(final)))
    icon = Image.open(lib.ASSETS / "items" / "painted" / f"{name}.png")
    stages.append(("icon", on_dark(icon, resample=Image.NEAREST)))
    for i, (stage, img) in enumerate(stages, 1):
        path = OUT / f"{name}_{i:02d}_{stage}.png"
        img.save(path, optimize=True)
        print("wrote", path)
    # A close-up of the same patch before and after the brushwork pass.
    w = raw.width
    box = (int(w * 0.30), int(w * 0.30), int(w * 0.62), int(w * 0.62))
    before = on_dark(raw).resize((w, w)).crop(box)
    after = on_dark(brush).resize((w, w)).crop(box)
    side = before.width * 2
    pair = Image.new("RGB", (side * 2 + 12, side), BG)
    pair.paste(before.resize((side, side), Image.NEAREST), (0, 0))
    pair.paste(after.resize((side, side), Image.NEAREST), (side + 12, 0))
    pair.save(OUT / f"{name}_brush_closeup.png", optimize=True)
    print("wrote", OUT / f"{name}_brush_closeup.png")
    radius_compare(name, raw)


def radius_compare(name, raw):
    """The finished look with brush radius 0 (none), 3, 5 (used) and 9, at the
    512 px close-up and at the 64 px the game shows."""
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    radii = (0, 3, 5, 9)
    cell = 256
    img = Image.new("RGB", (len(radii) * (cell + 12) + 12, cell + 200), BG)
    d = ImageDraw.Draw(img)
    for i, r in enumerate(radii):
        art = painted.finish_painted(raw, radius=r, outline_px=4)
        x = 12 + i * (cell + 12)
        img.paste(on_dark(art).resize((cell, cell)), (x, 12))
        small = art.resize((64, 64), Image.LANCZOS)
        img.paste(on_dark(small, size=64, resample=Image.NEAREST), (x, cell + 24))
        img.paste(on_dark(small, size=128, resample=Image.NEAREST), (x + 76, cell + 24))
        label = f"radius {r}" + (" (none)" if r == 0 else " (used)" if r == 5 else "")
        d.text((x, cell + 24 + 136), label, font=font, fill=(232, 226, 214))
    img.save(OUT / f"{name}_brush_radius.png", optimize=True)
    print("wrote", OUT / f"{name}_brush_radius.png")


def tone_curves():
    """Strips of light from 1/16 to 16 times 'white' (each step doubles it),
    shown through the Standard and the AgX view transforms."""
    lib.reset_scene(samples=4, transparent=False, sky=(0, 0, 0), sky_strength=0.0)
    sc = bpy.context.scene
    sc.cycles.use_denoising = False
    rows = [("white", (1.0, 1.0, 1.0)), ("torch orange", (1.0, 0.42, 0.08)), ("steel blue", (0.35, 0.5, 0.8))]
    for k, (_, color) in enumerate(rows):
        mat = bpy.data.materials.new(f"Ramp{k}")
        mat.use_nodes = True
        nt = mat.node_tree
        out = nt.nodes["Material Output"]
        nt.nodes.remove(nt.nodes["Principled BSDF"])
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (*color, 1.0)
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(tc.outputs["Generated"], sep.inputs[0])
        # strength = 2 ^ (8x - 4): x from 0 to 1 gives 1/16 ... 16.
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = 'MULTIPLY_ADD'
        nt.links.new(sep.outputs["X"], mul.inputs[0])
        mul.inputs[1].default_value = 8.0
        mul.inputs[2].default_value = -4.0
        pw = nt.nodes.new("ShaderNodeMath")
        pw.operation = 'POWER'
        pw.inputs[0].default_value = 2.0
        nt.links.new(mul.outputs[0], pw.inputs[1])
        nt.links.new(pw.outputs[0], em.inputs["Strength"])
        nt.links.new(em.outputs[0], out.inputs["Surface"])
        lib.box(f"Strip{k}", (8.0, 0.9, 0.01), (0, -k * 1.0, 0), mat=mat)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 8.0
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (0, -1.0, 5)
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 1024, 384, 100
    strips = {}
    for view, look in (('Standard', 'None'), ('AgX', 'AgX - Punchy')):
        sc.view_settings.view_transform, sc.view_settings.look = view, look
        strips[view] = lib.render(TMP / f"tone_{view}.png").convert("RGB")
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
    W, H = 1024 + 170, 2 * (384 + 40) + 50
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    for i, (view, title) in enumerate((('Standard', "Standard (the classic icons)"),
                                       ('AgX', "AgX - Punchy (the painted icons)"))):
        y = 10 + i * (384 + 40)
        d.text((170, y), title, font=bold, fill=(232, 226, 214))
        img.paste(strips[view], (170, y + 26))
        for k, (label, _) in enumerate(rows):
            d.text((10, y + 26 + k * 128 + 54), label, font=font, fill=(200, 192, 180))
    y = H - 30
    for j, label in enumerate(("1/16", "1/4", "1", "4", "16")):
        x = 170 + int(j / 4 * 1023)
        d.text((x - (0 if j == 0 else d.textlength(label, font=font) if j == 4 else 12), y), label, font=font,
               fill=(200, 192, 180))
    d.text((170 + 300, y - 4 - 16), "light intensity (each step right doubles it)", font=font, fill=(150, 142, 130))
    img.save(OUT / "tone_curves.png", optimize=True)
    print("wrote", OUT / "tone_curves.png")


if __name__ == "__main__":
    for item_name in sys.argv[1:] or ["shield"]:
        breakdown(item_name)
    tone_curves()
