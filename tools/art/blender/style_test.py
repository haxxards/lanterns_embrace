"""Painted-style test renders, for review only: nothing under assets/ changes.

Re-makes four inventory icons (longsword, round shield, healing potion, chain
mail) with more detailed, stylised models and the materials and finishing
pass in painted.py, and re-renders Garrick's sprite with the same materials.
For each it writes the plain render, the painted version, and the painted
version at in-game size.

    .venv-art/bin/python tools/art/blender/style_test.py OUT_DIR [longsword shield potion chain_mail garrick]
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))

import lib  # noqa: E402
import painted  # noqa: E402
import render_items as ri  # noqa: E402

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("style_test")
RENDER = 512
ICON = 64


# --------------------------------------------------------------------------
# Shape helpers
# --------------------------------------------------------------------------

def scene():
    lib.reset_scene(samples=64, transparent=True, sky=(0.2, 0.21, 0.24), sky_strength=0.5)
    bpy.context.scene.cycles.max_bounces = 8
    painted.studio()
    root = bpy.data.objects.new("Item", None)
    bpy.context.scene.collection.objects.link(root)
    return root


def tube(name, pts, radii, mat, parent, sides=14, caps=True):
    """Smooth tube along a polyline with per-point radii."""
    pts = [Vector(p) for p in pts]
    verts, faces = [], []
    for k, (p, r) in enumerate(zip(pts, radii)):
        d = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
        q = d.to_track_quat('Z', 'Y').to_matrix()
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append(p + q @ Vector((math.cos(a) * r, math.sin(a) * r, 0)))
    for s in range(len(pts) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((s * sides + i, s * sides + j, (s + 1) * sides + j, (s + 1) * sides + i))
    if caps:
        faces.append(tuple(range(sides))[::-1])
        top = (len(pts) - 1) * sides
        faces.append(tuple(range(top, top + sides)))
    return lib.mesh_object(name, verts, faces, mat=mat, parent=parent, smooth=True)


def ball(name, loc, r, mat, parent, scale=(1, 1, 1)):
    return ri.sphere(name, loc, r, mat, parent, scale=scale, seg=20)


def bevel(obj, width=0.004, segments=2):
    m = obj.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    return obj


def render_icon(name, elevation, angle=None):
    """Frames, renders at RENDER px and writes the three versions."""
    ri.RENDER = RENDER
    ri.frame(elevation, margin=0.08)
    raw = lib.render(OUT / f"{name}_plain.png")
    painted_img = painted.finish_painted(raw, radius=5, outline_px=4)
    painted_img.save(OUT / f"{name}_painted.png")
    small = painted_img.resize((ICON, ICON), Image.LANCZOS).filter(ImageFilter.UnsharpMask(1.0, 60, 2))
    shadow = Image.new("RGBA", small.size, (0, 0, 0, 0))
    shadow.putalpha(small.split()[3].point(lambda v: int(v * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(1.6))
    icon = Image.new("RGBA", small.size, (0, 0, 0, 0))
    icon.alpha_composite(shadow, (2, 2))
    icon.alpha_composite(small)
    icon.save(OUT / f"{name}_icon64.png")
    print("wrote", name)


# --------------------------------------------------------------------------
# Longsword: a fullered blade, swept quillons, a wrapped grip, a wheel pommel
# --------------------------------------------------------------------------

def blade_mesh(name, length, base_w, thick, mat, parent):
    stations = [(0.0, 1.0, 1.0), (0.25, 0.96, 1.0), (0.55, 0.9, 1.0), (0.8, 0.8, 0.0), (0.92, 0.55, 0.0)]
    verts, faces = [], []
    for f, wf, fuller in stations:
        x, w, t = f * length, base_w * wf / 2, thick / 2
        depth = t * (0.35 if fuller else 0.95)
        ring = [(x, -w, 0), (x, -0.45 * w, t), (x, -0.13 * w, depth), (x, 0.13 * w, depth), (x, 0.45 * w, t),
                (x, w, 0), (x, 0.45 * w, -t), (x, 0.13 * w, -depth), (x, -0.13 * w, -depth), (x, -0.45 * w, -t)]
        verts += ring
    n = 10
    for s in range(len(stations) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((s * n + i, s * n + j, (s + 1) * n + j, (s + 1) * n + i))
    tip = len(verts)
    verts.append((length, 0, 0))
    last = (len(stations) - 1) * n
    for i in range(n):
        faces.append((last + i, last + (i + 1) % n, tip))
    faces.append(tuple(range(n))[::-1])
    return lib.mesh_object(name, verts, faces, mat=mat, parent=parent)


def longsword():
    root = scene()
    steel = painted.metal("Blade", "#9aa1aa")
    gold = painted.gold("Brass")
    blade_mesh("Blade", 0.9, 0.09, 0.022, steel, root)
    # Quillons swept towards the blade, ending in knobs.
    arc = []
    for k in range(13):
        u = (k / 12) * 2 - 1
        arc.append((0.0 + 0.05 * u * u, 0.17 * u, 0.0))
    tube("Guard", arc, [0.016 + 0.006 * abs((k / 12) * 2 - 1) for k in range(13)], gold, root)
    for s in (-1, 1):
        ball(f"Knob{s}", (0.05, 0.17 * s, 0), 0.024, gold, root)
    bevel(lib.box("Langet", (0.06, 0.06, 0.035), (0.01, 0, 0), mat=gold, parent=root, bevel=0.01))
    ball("GuardGem", (0.01, 0, 0.02), 0.014, painted.glow("GuardGem", "#2a5ac8", 0.8, "#9fd0ff"), root, (1, 1, 0.6))
    # Leather-wrapped grip with brass ferrules.
    leather = painted.leather("Grip", "#4a2a18")
    lib.cylinder_between("GripCore", (-0.02, 0, 0), (-0.21, 0, 0), 0.018, mat=leather, parent=root, sides=16)
    helix = []
    for k in range(97):
        t = k / 96
        a = t * 2 * math.pi * 9
        helix.append((-0.025 - t * 0.18, math.cos(a) * 0.019, math.sin(a) * 0.019))
    tube("Wrap", helix, [0.006] * len(helix), leather, root, sides=8)
    for x in (-0.025, -0.205):
        ri.torus(f"Ferrule{x}", (x, 0, 0), 0.021, 0.007, gold, root, rot=(0, math.radians(90), 0))
    # Wheel pommel with a red stone.
    pom = ri.cyl("Pommel", (-0.25, 0, 0), 0.045, 0.03, gold, root, verts=32)
    bevel(pom, 0.006, 3)
    ri.torus("PommelRim", (-0.25, 0, 0.0), 0.045, 0.008, gold, root)
    ball("PommelGem", (-0.25, 0, 0.016), 0.02, painted.glow("PommelGem", "#b0141a", 0.8, "#ff7a5a"), root, (1, 1, 0.55))
    ri.diagonal(root, 40)
    render_icon("longsword", 72)


# --------------------------------------------------------------------------
# Round shield: separate planks, an iron rim with rivets, a riveted boss
# --------------------------------------------------------------------------

def plank(name, x0, x1, radius, thick, mat, parent, steps=10):
    top, bottom = [], []
    for k in range(steps + 1):
        x = x0 + (x1 - x0) * k / steps
        z = math.sqrt(max(radius * radius - x * x, 0.0))
        top.append((x, 0.0, z))
        bottom.append((x, 0.0, -z))
    outline = top + bottom[::-1]
    obj = lib.mesh_object(name, outline, [tuple(range(len(outline)))], mat=mat, parent=parent)
    sol = obj.modifiers.new("Thick", 'SOLIDIFY')
    sol.thickness = thick
    sol.offset = 1.0
    bevel(obj, 0.004, 2)
    return obj


def shield():
    root = scene()
    R = 0.32
    tints = ["#6b4a30", "#5e3f28", "#735034", "#62432b", "#6e4c31"]
    n = 5
    for i in range(n):
        x0 = -R + i * 2 * R / n + 0.004
        x1 = -R + (i + 1) * 2 * R / n - 0.004
        p = plank(f"Plank{i}", x0, x1, R - 0.01, 0.035, painted.wood(f"Plank{i}", tints[i], 5.0, along="Z"), root)
        p.location.y = 0.004 * ((i * 7) % 3 - 1)
    # Worn steel rim and boss, as in the reference (pale, scuffed, not blackened iron).
    steel = painted.metal("Rim", "#8f9297", rough=0.4, metallic=0.55)
    rim = ri.torus("Rim", (0, 0.0, 0), R - 0.004, 0.026, steel, root, rot=(math.radians(90), 0, 0))
    rim.scale = (1.0, 1.0, 0.75)
    for k in range(16):
        a = 2 * math.pi * k / 16
        ball(f"Rivet{k}", (math.cos(a) * (R - 0.045), -0.04, math.sin(a) * (R - 0.045)), 0.011, steel, root)
    boss = painted.metal("Boss", "#a3a6ab", rough=0.34, metallic=0.55)
    ball("Boss", (0, -0.035, 0), 0.085, boss, root, scale=(1, 0.6, 1))
    ri.torus("Flange", (0, -0.038, 0), 0.1, 0.014, steel, root, rot=(math.radians(90), 0, 0))
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        ball(f"BossRivet{k}", (math.cos(a) * 0.1, -0.05, math.sin(a) * 0.1), 0.01, steel, root)
    render_icon("shield", 20)


# --------------------------------------------------------------------------
# Healing potion: a bulbous flask in a brass cage, glowing red
# --------------------------------------------------------------------------

def potion():
    root = scene()
    prof = [(0.001, 0.0), (0.06, 0.004), (0.075, 0.02), (0.11, 0.06), (0.125, 0.11), (0.115, 0.16), (0.08, 0.2),
            (0.04, 0.225), (0.032, 0.25), (0.032, 0.29), (0.042, 0.3)]
    ri.lathe("Flask", prof, painted.glass("Glass"), root, sides=40)
    inner = [(0.001, 0.008), (0.07, 0.014), (0.105, 0.06), (0.117, 0.1), (0.116, 0.125), (0.001, 0.125)]
    ri.lathe("Liquid", inner, painted.glow("Liquid", "#9a0e16", 1.1, "#ff6a4a"), root, sides=40)
    ball("Bubble1", (0.03, -0.06, 0.09), 0.012, painted.glass("Bubble"), root)
    ball("Bubble2", (-0.04, -0.07, 0.06), 0.008, painted.glass("Bubble2"), root)
    gold = painted.gold("Cage")
    # Bands at the foot, the belly and the shoulder; vertical straps between.
    for z, r, th in ((0.012, 0.072, 0.012), (0.11, 0.128, 0.011), (0.2, 0.085, 0.01), (0.255, 0.036, 0.012)):
        ri.torus(f"Band{z}", (0, 0, z), r, th, gold, root)
    for k in range(6):
        a = 2 * math.pi * k / 6
        pts = [(math.cos(a) * (r + 0.004), math.sin(a) * (r + 0.004), z)
               for r, z in ((0.072, 0.012), (0.105, 0.05), (0.124, 0.11), (0.115, 0.16), (0.085, 0.2))]
        tube(f"Strap{k}", pts, [0.006] * len(pts), gold, root, sides=8)
        ball(f"Stud{k}", (math.cos(a) * 0.136, math.sin(a) * 0.136, 0.11), 0.013, gold, root)
    # Cork, a wax seal and a loop of cord.
    ri.cyl("Cork", (0, 0, 0.315), 0.03, 0.05, painted.wood("Cork", "#b58a55", 12.0, along="Z"), root, verts=20)
    wax = painted.leather("Wax", "#8a1a14")
    ball("Seal", (0, 0, 0.342), 0.036, wax, root, scale=(1, 1, 0.45))
    cord = painted.leather("Cord", "#c8b07a")
    loop = [(0.034 + 0.05 * math.sin(t / 10 * math.pi), -0.01, 0.27 - 0.09 * math.sin(t / 20 * math.pi))
            for t in range(11)]
    tube("Cord", loop, [0.005] * len(loop), cord, root, sides=6)
    render_icon("potion_of_healing", 22)


# --------------------------------------------------------------------------
# Chain mail: a shirt of rings with leather trim and buckled straps
# --------------------------------------------------------------------------

def chain_mail():
    root = scene()
    mail = painted.chain("Mail", "#b4b9c0", rings=34.0)
    prof = [(0.07, 0.74), (0.15, 0.725), (0.215, 0.66), (0.2, 0.5), (0.18, 0.38), (0.2, 0.2), (0.235, 0.04),
            (0.24, 0.0)]
    body = ri.lathe("Hauberk", prof, mail, root, sides=36)
    body.scale = (1.0, 0.55, 1.0)
    for s in (-1, 1):
        ball(f"Shoulder{s}", (s * 0.2, 0, 0.64), 0.08, mail, root, scale=(1.0, 0.75, 0.75))
        tube(f"Sleeve{s}", [(s * 0.21, 0, 0.64), (s * 0.29, 0, 0.55), (s * 0.34, 0, 0.44)], [0.075, 0.07, 0.068],
             mail, root, sides=20)
    leather = painted.leather("Trim", "#6a3a22")
    gold = painted.gold("Buckle")
    collar = ri.torus("Collar", (0, 0, 0.72), 0.085, 0.022, leather, root)
    collar.scale = (1.0, 0.7, 1.0)
    hem = ri.torus("Hem", (0, 0, 0.012), 0.235, 0.018, leather, root)
    hem.scale = (1.0, 0.55, 1.0)
    for s in (-1, 1):
        ri.torus(f"Cuff{s}", (s * 0.338, 0, 0.445), 0.07, 0.016, leather, root,
                 rot=(0, math.radians(-s * 52), 0))
    # A belt and three buckled straps down the front.
    belt = ri.torus("Belt", (0, 0, 0.3), 0.19, 0.022, leather, root)
    belt.scale = (1.0, 0.58, 1.0)
    for k, z in enumerate((0.6, 0.47, 0.34)):
        bevel(lib.box(f"Strap{k}", (0.11, 0.02, 0.035), (0, -0.112, z), mat=leather, parent=root, bevel=0.006))
        bevel(lib.box(f"Buckle{k}", (0.035, 0.024, 0.045), (0.02, -0.122, z), mat=gold, parent=root, bevel=0.005))
    # The leather placket the straps fasten across, as on a gambeson-backed hauberk.
    bevel(lib.box("Placket", (0.045, 0.012, 0.42), (0, -0.108, 0.5), mat=leather, parent=root, bevel=0.004))
    bevel(lib.box("BeltBuckle", (0.06, 0.03, 0.06), (0, -0.115, 0.3), mat=gold, parent=root, bevel=0.008))
    render_icon("chain_mail", 18)


# --------------------------------------------------------------------------
# Garrick's sprite with the painted materials
# --------------------------------------------------------------------------

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
        cam, res = lib.frame_oblique(objs, margin_px=4)
        raw = lib.render(OUT / "garrick_plain.png")
        art = painted.finish_painted(raw, radius=6, outline_px=5)
        art.resize((res[0] * 4, res[1] * 4), Image.LANCZOS).save(OUT / "garrick_painted.png")
        game = art.resize(res, Image.LANCZOS).filter(ImageFilter.UnsharpMask(0.8, 50, 2))
        game.save(OUT / "garrick_game.png")
        _ = cam
    finally:
        rc.mat = original
        lib.SUPERSAMPLE = 2
    print("wrote garrick", res)


SUBJECTS = {"longsword": longsword, "shield": shield, "potion": potion, "chain_mail": chain_mail,
            "garrick": garrick}


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name in sys.argv[2:] or list(SUBJECTS):
        SUBJECTS[name]()
