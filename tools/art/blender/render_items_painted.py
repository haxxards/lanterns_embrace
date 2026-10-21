"""Inventory icons in the "painted" style.

The same 37 items as render_items.py, re-modelled with more detail (fullered
blades, wrapped grips, riveted rims, mail rings, buckles...) and rendered with
the painted materials, lighting and finishing pass from painted.py. Which set
the game shows is chosen by "art_style" in data/config/game_config.json.

docs/PAINTED_STYLE.md explains how the look is made, step by step.

Output: assets/items/painted/<name>.png, 64x64 (rendered at 512 and shrunk).
"""
import math
import tempfile
from pathlib import Path

import bpy
import bmesh  # noqa: I001 (bmesh is only importable once bpy is loaded)
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image, ImageFilter

import lib
import painted
import render_items as ri

RENDER = 512
ICON = 64
SAMPLES = 64
OUT_DIR = lib.ASSETS / "items" / "painted"
# When set (a Path), the full-size plain and painted renders are kept there too.
KEEP_DIR = None

# name -> (build function, camera elevation in degrees)
ALL = {}


def item(name, elevation):
    def register(fn):
        ALL[name] = (fn, elevation)
        return fn
    return register


# --------------------------------------------------------------------------
# Scene, rendering and shape helpers
# --------------------------------------------------------------------------

def scene():
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=(0.2, 0.21, 0.24), sky_strength=0.5)
    bpy.context.scene.cycles.max_bounces = 8
    painted.studio()
    root = bpy.data.objects.new("Item", None)
    bpy.context.scene.collection.objects.link(root)
    return root


def render_icon(name, elevation):
    """Frames the model, renders it at RENDER px, paints it and shrinks it to
    the 64 px icon with a soft drop shadow."""
    ri.RENDER = RENDER
    ri.frame(elevation, margin=0.08)
    tmp = KEEP_DIR or Path(tempfile.gettempdir())
    raw = lib.render(tmp / f"{name}_plain.png")
    art = painted.finish_painted(raw, radius=5, outline_px=4)
    if KEEP_DIR:
        art.save(KEEP_DIR / f"{name}_painted.png")
    small = art.resize((ICON, ICON), Image.LANCZOS).filter(ImageFilter.UnsharpMask(1.0, 60, 2))
    shadow = Image.new("RGBA", small.size, (0, 0, 0, 0))
    shadow.putalpha(small.split()[3].point(lambda v: int(v * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(1.6))
    icon = Image.new("RGBA", small.size, (0, 0, 0, 0))
    icon.alpha_composite(shadow, (2, 2))
    icon.alpha_composite(small)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.png"
    icon.save(path)
    if not KEEP_DIR:
        (tmp / f"{name}_plain.png").unlink(missing_ok=True)
    print("wrote", path)


def group(name, parent, loc=(0, 0, 0), rot=(0, 0, 0)):
    """An empty to build a part in its own coordinates (then placed and turned)."""
    g = bpy.data.objects.new(name, None)
    lib.link(g, parent)
    g.location = loc
    g.rotation_euler = rot
    return g


def tube(name, pts, radii, mat, parent, sides=14, caps=True):
    """Smooth tube along a polyline with per-point radii."""
    pts = [Vector(p) for p in pts]
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * len(pts)
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


def plate(name, outline, thick, mat, parent, plane="XY", bevel_w=0.003):
    """A flat shape cut from sheet metal (or leather, or a feather): the 2D
    `outline` in the given plane, thickened and with softened edges."""
    if plane == "XY":
        verts = [(x, y, 0.0) for x, y in outline]
    else:  # "XZ"
        verts = [(x, 0.0, z) for x, z in outline]
    obj = lib.mesh_object(name, verts, [tuple(range(len(verts)))], mat=mat, parent=parent)
    sol = obj.modifiers.new("Thick", 'SOLIDIFY')
    sol.thickness = thick
    sol.offset = 0.0
    if bevel_w > 0:
        bevel(obj, bevel_w, 2)
    return obj


def fix_normals(obj):
    """Points every face of a hand-built mesh outwards."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def wedge(name, outline, center, thickness, mat, parent, cheek=0.72, cheek_thick=None):
    """A forged blade from a 2D outline in the XY plane: a flat cheek in the
    middle (`cheek` of the way out from `center`, `cheek_thick` thick) and a
    ground bevel from there to the outline, whose thickness at each point is
    `thickness(x, y)`. The bevel's sloping faces catch the light differently
    from the cheek, which is what makes a blade read as forged steel."""
    cx, cy = center
    tc = cheek_thick if cheek_thick is not None else thickness(cx, cy)
    verts = [(cx, cy, tc / 2), (cx, cy, -tc / 2)]
    for x, y in outline:
        qx, qy = cx + (x - cx) * cheek, cy + (y - cy) * cheek
        t = thickness(x, y)
        verts += [(qx, qy, tc / 2), (qx, qy, -tc / 2), (x, y, t / 2), (x, y, -t / 2)]
    faces = []
    n = len(outline)
    for i in range(n):
        a, b = 2 + 4 * i, 2 + 4 * ((i + 1) % n)
        faces += [(0, a, b), (1, b + 1, a + 1),                    # cheeks
                  (a, a + 2, b + 2, b), (a + 1, b + 1, b + 3, a + 3),  # bevels
                  (a + 2, a + 3, b + 3, b + 2)]                  # the edge itself
    return fix_normals(lib.mesh_object(name, verts, faces, mat=mat, parent=parent))


def flat_shaded(obj):
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def oriented_torus(name, loc, major, minor, mat, parent, x_axis, z_axis, stretch=1.0):
    """A torus whose ring plane is spanned by `x_axis` and the third axis, its
    hole along `z_axis` (both unit vectors), stretched along x (chain links)."""
    o = ri.torus(name, (0, 0, 0), major, minor, mat, parent)
    x = Vector(x_axis).normalized()
    z = Vector(z_axis).normalized()
    y = z.cross(x)
    o.matrix_local = Matrix.Translation(Vector(loc)) @ Matrix((
        (x[0], y[0], z[0], 0), (x[1], y[1], z[1], 0), (x[2], y[2], z[2], 0), (0, 0, 0, 1))) @ \
        Matrix.Diagonal((stretch, 1.0, 1.0, 1.0))
    return o


def wrapped_grip(name, x0, x1, r, mat, parent, turns=8, cord=0.006, core_mat=None):
    """A grip along X: a core with a cord or strip spiralled round it."""
    lib.cylinder_between(name + "Core", (x0, 0, 0), (x1, 0, 0), r, mat=core_mat or mat, parent=parent, sides=16)
    n = int(turns * 12)
    helix = []
    for k in range(n + 1):
        t = k / n
        a = t * 2 * math.pi * turns
        helix.append((x0 + (x1 - x0) * t, math.cos(a) * (r + cord * 0.3), math.sin(a) * (r + cord * 0.3)))
    tube(name + "Wrap", helix, cord, mat, parent, sides=8)


def ring_x(name, x, r, minor, mat, parent):
    """A collar ring around the X axis (ferrules, bands on a haft)."""
    return ri.torus(name, (x, 0, 0), r, minor, mat, parent, rot=(0, math.radians(90), 0))


def blade_mesh(name, length, base_w, thick, mat, parent, x0=0.0):
    """A double-edged blade along +X with a fuller (groove) down its first part."""
    stations = [(0.0, 1.0, 1.0), (0.25, 0.96, 1.0), (0.55, 0.9, 1.0), (0.8, 0.8, 0.0), (0.92, 0.55, 0.0)]
    verts, faces = [], []
    for f, wf, fuller in stations:
        x, w, t = x0 + f * length, base_w * wf / 2, thick / 2
        depth = t * (0.35 if fuller else 0.95)
        verts += [(x, -w, 0), (x, -0.45 * w, t), (x, -0.13 * w, depth), (x, 0.13 * w, depth), (x, 0.45 * w, t),
                  (x, w, 0), (x, 0.45 * w, -t), (x, 0.13 * w, -depth), (x, -0.13 * w, -depth), (x, -0.45 * w, -t)]
    n = 10
    for s in range(len(stations) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((s * n + i, s * n + j, (s + 1) * n + j, (s + 1) * n + i))
    tip = len(verts)
    verts.append((x0 + length, 0, 0))
    last = (len(stations) - 1) * n
    for i in range(n):
        faces.append((last + i, last + (i + 1) % n, tip))
    faces.append(tuple(range(n))[::-1])
    return lib.mesh_object(name, verts, faces, mat=mat, parent=parent)


def lathe(name, profile, mat, parent, sides=36, flat=False):
    o = ri.lathe(name, profile, mat, parent, sides=sides)
    return flat_shaded(o) if flat else o


def radius_at(profile, z):
    """Radius of a lathe profile [(r, z), ...] at height z (linear between points)."""
    pts = sorted(profile, key=lambda p: p[1])
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-9)
    return pts[0][0] if z < pts[0][1] else pts[-1][0]


# --------------------------------------------------------------------------
# Weapons (lying diagonally, seen from high above)
# --------------------------------------------------------------------------

@item("longsword", 72)
def longsword(root):
    steel = painted.metal("Blade", "#9aa1aa")
    gold = painted.gold("Brass")
    blade_mesh("Blade", 0.9, 0.09, 0.022, steel, root)
    # Quillons swept towards the blade, ending in knobs.
    arc = [(0.05 * ((k / 12) * 2 - 1) ** 2, 0.17 * ((k / 12) * 2 - 1), 0.0) for k in range(13)]
    tube("Guard", arc, [0.016 + 0.006 * abs((k / 12) * 2 - 1) for k in range(13)], gold, root)
    for s in (-1, 1):
        ball(f"Knob{s}", (0.05, 0.17 * s, 0), 0.024, gold, root)
    bevel(lib.box("Langet", (0.06, 0.06, 0.035), (0.01, 0, 0), mat=gold, parent=root, bevel=0.01))
    ball("GuardGem", (0.01, 0, 0.02), 0.014, painted.glow("GuardGem", "#2a5ac8", 0.8, "#9fd0ff"), root, (1, 1, 0.6))
    # Leather-wrapped grip with brass ferrules.
    wrapped_grip("Grip", -0.025, -0.205, 0.018, painted.leather("Grip", "#4a2a18"), root, turns=9)
    for x in (-0.025, -0.205):
        ring_x(f"Ferrule{x}", x, 0.021, 0.007, gold, root)
    # Wheel pommel with a red stone.
    pom = ri.cyl("Pommel", (-0.25, 0, 0), 0.045, 0.03, gold, root, verts=32)
    bevel(pom, 0.006, 3)
    ri.torus("PommelRim", (-0.25, 0, 0.0), 0.045, 0.008, gold, root)
    ball("PommelGem", (-0.25, 0, 0.016), 0.02, painted.glow("PommelGem", "#b0141a", 0.8, "#ff7a5a"), root,
         (1, 1, 0.55))
    ri.diagonal(root, 40)


@item("shortsword", 72)
def shortsword(root):
    steel = painted.metal("Blade", "#9aa1aa")
    guard = painted.metal("Guard", "#7c8087", rough=0.45)
    blade_mesh("Blade", 0.6, 0.085, 0.02, steel, root)
    # A straight cross-guard, thicker at the ends.
    pts = [(0.0, 0.14 * ((k / 8) * 2 - 1), 0.0) for k in range(9)]
    tube("Guard", pts, [0.012 + 0.012 * abs((k / 8) * 2 - 1) ** 2 for k in range(9)], guard, root)
    bevel(lib.box("Langet", (0.04, 0.05, 0.03), (0.005, 0, 0), mat=guard, parent=root, bevel=0.008))
    wrapped_grip("Grip", -0.02, -0.15, 0.017, painted.leather("Grip", "#6a4228"), root, turns=6, cord=0.007)
    ring_x("Ferrule", -0.15, 0.02, 0.006, guard, root)
    ball("Pommel", (-0.18, 0, 0), 0.032, guard, root, scale=(0.8, 1, 1))
    ball("PommelCap", (-0.21, 0, 0), 0.012, guard, root)
    ri.diagonal(root, 40)


@item("dagger", 72)
def dagger(root):
    steel = painted.metal("Blade", "#a3a9b1")
    brass = painted.gold("Brass")
    blade_mesh("Blade", 0.32, 0.075, 0.018, steel, root)
    # A short guard curling slightly towards the blade.
    pts = [(0.025 * ((k / 8) * 2 - 1) ** 2, 0.085 * ((k / 8) * 2 - 1), 0.0) for k in range(9)]
    tube("Guard", pts, 0.011, brass, root)
    for s in (-1, 1):
        ball(f"Knob{s}", (0.025, 0.085 * s, 0), 0.015, brass, root)
    wrapped_grip("Grip", -0.015, -0.11, 0.014, painted.leather("Grip", "#2e1c12"), root, turns=6, cord=0.005)
    ball("Pommel", (-0.13, 0, 0), 0.024, brass, root)
    ri.diagonal(root, 40)


@item("rapier", 72)
def rapier(root):
    steel = painted.metal("Blade", "#a3a9b1", rough=0.36)
    gold = painted.gold("Hilt")
    blade_mesh("Blade", 0.95, 0.034, 0.012, steel, root)
    # Straight quillons with knobs, a guard ring round the blade, and a
    # knuckle bow sweeping back to the pommel.
    tube("Quillons", [(0.0, -0.12, 0), (0.0, 0.12, 0)], 0.008, gold, root, sides=10)
    for s in (-1, 1):
        ball(f"Knob{s}", (0.0, 0.12 * s, 0), 0.014, gold, root)
    oriented_torus("GuardRing", (0.025, 0, 0), 0.04, 0.006, gold, root, (0, 1, 0), (1, 0, 0))
    bow = [(0.0, -0.11, 0.0), (-0.035, -0.085, 0.004), (-0.08, -0.07, 0.006), (-0.125, -0.05, 0.004),
           (-0.155, -0.02, 0.0)]
    tube("KnuckleBow", bow, 0.0065, gold, root, sides=10)
    for s in (-1, 1):  # side rings of a swept hilt
        oriented_torus(f"SideRing{s}", (0.03, 0.045 * s, 0), 0.03, 0.005, gold, root, (1, 0, 0), (0, 0, 1),
                       stretch=1.3)
    wrapped_grip("Grip", -0.015, -0.14, 0.014, gold, root, turns=11, cord=0.0035,
                 core_mat=painted.leather("GripCore", "#2a1a10"))
    ball("Pommel", (-0.165, 0, 0), 0.026, gold, root, scale=(1.3, 1, 1))
    ri.diagonal(root, 40)


@item("greataxe", 72)
def greataxe(root):
    haft = painted.wood("Haft", "#5e4228", 6.0, along="X")
    steel = painted.metal("Axe", "#8a9098", rough=0.34, metallic=0.88)
    honed = painted.metal("Edge", "#d4d8de", edge="#ffffff", rough=0.25, metallic=0.8, scratches=False)
    iron = painted.iron("Socket")
    lib.cylinder_between("Haft", (-0.62, 0, 0), (0.5, 0, 0), 0.022, mat=haft, parent=root, sides=16)
    wrapped_grip("Wrap", -0.6, -0.36, 0.023, painted.leather("Wrap", "#4a2c1a"), root, turns=7, cord=0.007)
    lib.cylinder_between("Butt", (-0.62, 0, 0), (-0.68, 0, 0), 0.026, 0.008, mat=iron, parent=root, sides=16)
    # Two crescent bits either side of an iron socket.
    upper = [(0.33, 0.03), (0.43, 0.03), (0.46, 0.09), (0.53, 0.15), (0.57, 0.21), (0.55, 0.25), (0.48, 0.27),
             (0.38, 0.278), (0.28, 0.27), (0.21, 0.25), (0.19, 0.21), (0.23, 0.15), (0.3, 0.09)]
    for s in (-1, 1):  # thick by the socket, ground down to a thin, bright cutting edge
        wedge(f"Bit{s}", [(x, s * y) for x, y in upper], (0.38, s * 0.12),
              lambda x, y: 0.03 - 0.026 * min(1.0, abs(y) / 0.26) ** 2, steel, root, cheek_thick=0.03)
        tube(f"Honed{s}", [(x, s * (y - 0.003), 0.0) for x, y in upper[3:10]], 0.006, honed, root, sides=6)
    socket = ri.cyl("Socket", (0.38, 0, 0), 0.034, 0.17, iron, root, rot=(0, math.radians(90), 0), verts=20)
    bevel(socket, 0.006, 2)
    for x in (0.31, 0.45):
        ring_x(f"Collar{x}", x, 0.035, 0.007, iron, root)
    for x in (0.35, 0.41):
        ball(f"Rivet{x}", (x, 0, 0.036), 0.008, iron, root)
    # Rolled 30 degrees about the haft: lying flat, the broad faces would mirror
    # the overhead light straight back at the camera as one pale slab.
    root.rotation_euler = (math.radians(30), 0, math.radians(40))


@item("mace", 70)
def mace(root):
    lib.cylinder_between("Shaft", (-0.38, 0, 0), (0.3, 0, 0), 0.017, mat=painted.wood("Haft", "#5e4228", 6.0, "X"),
                         parent=root, sides=14)
    wrapped_grip("Wrap", -0.37, -0.2, 0.018, painted.leather("Wrap", "#4a2c1a"), root, turns=6, cord=0.006)
    iron = painted.metal("Head", "#8a8e94", rough=0.42, metallic=0.6)
    ball("Pommel", (-0.395, 0, 0), 0.026, iron, root)
    # A solid, egg-shaped head with eight low flanges standing out of it, so
    # from above it reads as a heavy lump, not a cage.
    ball("Core", (0.37, 0, 0), 0.066, iron, root, scale=(1.3, 1, 1))
    fin = [(0.3, 0.04), (0.32, 0.075), (0.37, 0.094), (0.42, 0.086), (0.45, 0.06), (0.45, 0.04)]
    for i in range(8):
        f = plate(f"Flange{i}", fin, 0.02, iron, root, plane="XZ", bevel_w=0.005)
        f.rotation_euler = (math.tau * i / 8 + 0.2, 0, 0)
    lib.cylinder_between("Spike", (0.45, 0, 0), (0.51, 0, 0), 0.03, 0.003, mat=iron, parent=root, sides=16)
    for x in (0.29, 0.45):
        ring_x(f"Collar{x}", x, 0.047, 0.009, iron, root)
    ri.diagonal(root, 40)


@item("quarterstaff", 74)
def quarterstaff(root):
    ash = painted.wood("Ash", "#8a6a44", 4.0, along="X")
    lib.cylinder_between("Staff", (-0.84, 0, 0), (0.84, 0, 0), 0.036, mat=ash, parent=root, sides=18)
    iron = painted.iron("Caps")
    for s in (-1, 1):
        lib.cylinder_between(f"Cap{s}", (s * 0.76, 0, 0), (s * 0.87, 0, 0), 0.041, 0.039, mat=iron, parent=root,
                             sides=18)
        ring_x(f"CapRing{s}", s * 0.76, 0.042, 0.007, iron, root)
        for k in range(3):
            ball(f"Stud{s}{k}", (s * 0.815, math.cos(k * 2.1) * 0.041, math.sin(k * 2.1) * 0.041), 0.007, iron,
                 root)
    leather = painted.leather("Wrap", "#4a3020")
    wrapped_grip("Wrap", -0.13, 0.13, 0.037, leather, root, turns=7, cord=0.008)
    cord = painted.leather("Cord", "#b89a6a")
    for x in (-0.15, 0.15):
        ring_x(f"Binding{x}", x, 0.04, 0.006, cord, root)
    ri.diagonal(root, 40)


@item("warhammer", 70)
def warhammer(root):
    lib.cylinder_between("Shaft", (-0.42, 0, 0), (0.3, 0, 0), 0.017, mat=painted.wood("Haft", "#5e4228", 6.0, "X"),
                         parent=root, sides=14)
    wrapped_grip("Wrap", -0.41, -0.22, 0.018, painted.leather("Wrap", "#4a2c1a"), root, turns=7, cord=0.006)
    steel = painted.metal("Head", "#8e949b")
    ball("Pommel", (-0.43, 0, 0), 0.024, steel, root)
    bevel(lib.box("Block", (0.085, 0.08, 0.07), (0.32, 0, 0), mat=steel, parent=root), 0.008)
    # Hammer face on one side, a curved spike on the other, a point on top.
    bevel(lib.box("Face", (0.08, 0.07, 0.075), (0.32, -0.07, 0), mat=steel, parent=root), 0.006)
    bevel(lib.box("FacePlate", (0.088, 0.016, 0.083), (0.32, -0.108, 0), mat=steel, parent=root), 0.004)
    spike = [(0.32, 0.04 + 0.13 * t, 0.0) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
    spike = [(x - 0.03 * t * t, y, z) for (x, y, z), t in zip(spike, (0.0, 0.25, 0.5, 0.75, 1.0))]
    tube("Spike", spike, [0.03, 0.024, 0.017, 0.01, 0.002], steel, root, sides=4)
    lib.cylinder_between("Point", (0.36, 0, 0), (0.45, 0, 0), 0.022, 0.002, mat=steel, parent=root, sides=4)
    for s in (-1, 1):  # langets: iron strips running down the haft, riveted
        bevel(lib.box(f"Langet{s}", (0.14, 0.014, 0.006), (0.22, 0, s * 0.018), mat=steel, parent=root), 0.002)
        for x in (0.18, 0.25):
            ball(f"Rivet{s}{x}", (x, 0, s * 0.022), 0.005, steel, root)
    ri.diagonal(root, 40)


@item("shortbow", 74)
def shortbow(root):
    yew = painted.wood("Yew", "#8a5a2e", 5.0, along="X")
    pts, radii = [], []
    for i in range(33):
        t = i / 32 * 2 - 1
        y = -0.09 * (1 - t * t) - 0.9 * max(0.0, abs(t) - 0.8) ** 2  # tips curl away (recurve)
        pts.append((t * 0.55, y, 0.0))
        radii.append(0.024 - 0.013 * abs(t) ** 1.4)
    tube("Limbs", pts, radii, yew, root, sides=10)
    horn = painted.wood("Horn", "#3a2a1e", 9.0, along="X")
    for s, p in ((-1, pts[0]), (1, pts[-1])):
        ball(f"Nock{s}", p, 0.014, horn, root, scale=(1.4, 1, 1))
    leather = painted.leather("Grip", "#3b2616")
    g = group("GripAt", root, (0, -0.09, 0))
    wrapped_grip("Grip", -0.075, 0.075, 0.025, leather, g, turns=6, cord=0.006)
    string = painted.cloth("String", "#e2d8bf", weave=400.0)
    tube("String", [pts[1], pts[-2]], 0.004, string, root, sides=6)
    ri.diagonal(root, 40)


def arrow(root, i, y, angle, fletch):
    a = group(f"Arrow{i}", root, (-0.05, y, 0.012 * (i % 2)), (0, 0, math.radians(angle)))
    lib.cylinder_between("Shaft", (-0.33, 0, 0), (0.33, 0, 0), 0.007,
                         mat=painted.wood(f"Shaft{i}", "#b08e5e", 10.0, "X"), parent=a, sides=10)
    head = painted.metal(f"Head{i}", "#9aa0a8")
    plate("Head", [(0.33, -0.012), (0.37, -0.028), (0.43, 0.0), (0.37, 0.028), (0.33, 0.012)], 0.006, head, a,
          bevel_w=0.002)
    lib.cylinder_between("Socket", (0.31, 0, 0), (0.345, 0, 0), 0.009, 0.006, mat=head, parent=a, sides=10)
    for s in (-1, 1):
        plate(f"Vane{s}", [(-0.33, 0.0), (-0.2, 0.0), (-0.22, s * 0.012), (-0.27, s * 0.03), (-0.33, s * 0.034)],
              0.003, fletch, a, bevel_w=0.0)
    lib.cylinder_between("Nock", (-0.33, 0, 0), (-0.35, 0, 0), 0.008, mat=painted.leather(f"Nock{i}", "#2a1a10"),
                         parent=a, sides=10)


@item("arrows", 70)
def arrows(root):
    for i, (y, angle) in enumerate(((-0.035, 4.0), (0.0, 0.0), (0.035, -4.0))):
        color = "#b03a2e" if i == 1 else "#e2dccb"
        arrow(root, i, y, angle, painted.cloth(f"Fletch{i}", color, weave=300.0))
    tie = painted.leather("Tie", "#5a3a22")
    for x in (-0.1, -0.075):
        t = ri.torus(f"Tie{x}", (x, 0, 0.005), 0.05, 0.007, tie, root, rot=(0, math.radians(90), 0))
        t.scale = (1.0, 1.0, 0.45)
    ri.diagonal(root, 40)


# --------------------------------------------------------------------------
# Armour and clothing (standing, seen from the front)
# --------------------------------------------------------------------------

SHIRT = [(0.07, 0.74), (0.15, 0.725), (0.215, 0.66), (0.2, 0.5), (0.18, 0.38), (0.2, 0.2), (0.235, 0.04),
         (0.24, 0.0)]
VEST = [(0.07, 0.64), (0.15, 0.625), (0.21, 0.57), (0.2, 0.42), (0.18, 0.3), (0.19, 0.12), (0.205, 0.0)]


def body(name, profile, mat, root):
    o = lathe(name, profile, mat, root)
    o.scale = (1.0, 0.55, 1.0)
    return o


def front(profile, x, z, out=0.0):
    """The point on the front (-y) of a body() at sideways offset x and height z."""
    r = radius_at(profile, z)
    return (x, -0.55 * math.sqrt(max(r * r - x * x, 0.0)) - out, z)


def mail_shirt(root, ring_color, height, sleeve_len, belt=True, straps=True):
    k = height / 0.74
    prof = [(r, z * k) for r, z in SHIRT]
    mail = painted.chain("Mail", ring_color, rings=34.0)
    body("Hauberk", prof, mail, root)
    top = 0.64 * k
    for s in (-1, 1):
        ball(f"Shoulder{s}", (s * 0.2, 0, top), 0.08, mail, root, scale=(1.0, 0.75, 0.75))
        end = (s * (0.21 + 0.13 * sleeve_len), 0, top - 0.2 * sleeve_len)
        tube(f"Sleeve{s}", [(s * 0.21, 0, top), (s * (0.21 + 0.08 * sleeve_len), 0, top - 0.09 * sleeve_len), end],
             [0.075, 0.07, 0.068], mail, root, sides=20)
        ri.torus(f"Cuff{s}", end, 0.07, 0.016, painted.leather("Cuff", "#6a3a22"), root,
                 rot=(0, math.radians(-s * 52), 0))
    leather = painted.leather("Trim", "#6a3a22")
    gold = painted.gold("Buckle")
    collar = ri.torus("Collar", (0, 0, prof[0][1] - 0.02), 0.085, 0.022, leather, root)
    collar.scale = (1.0, 0.7, 1.0)
    hem = ri.torus("Hem", (0, 0, 0.012), 0.235, 0.018, leather, root)
    hem.scale = (1.0, 0.55, 1.0)
    if belt:
        bz = 0.3 * k
        b = ri.torus("Belt", (0, 0, bz), radius_at(prof, bz) - 0.005, 0.022, leather, root)
        b.scale = (1.0, 0.58, 1.0)
        bevel(lib.box("BeltBuckle", (0.06, 0.03, 0.06), front(prof, 0, bz, 0.008), mat=gold, parent=root), 0.008)
    if straps:
        for i, z in enumerate((0.6 * k, 0.47 * k, 0.34 * k)):
            p = front(prof, 0, z, 0.004)
            bevel(lib.box(f"Strap{i}", (0.11, 0.02, 0.035), p, mat=leather, parent=root), 0.006)
            bevel(lib.box(f"StrapBuckle{i}", (0.035, 0.024, 0.045), (0.02, p[1] - 0.01, z), mat=gold, parent=root),
                  0.005)
        bevel(lib.box("Placket", (0.045, 0.012, 0.42 * k), front(prof, 0, 0.5 * k, -0.002), mat=leather,
                      parent=root), 0.004)


@item("chain_mail", 18)
def chain_mail(root):
    mail_shirt(root, "#b4b9c0", 0.74, 1.0)


@item("chain_shirt", 18)
def chain_shirt(root):
    mail_shirt(root, "#aab0b8", 0.56, 0.55, belt=False, straps=False)


def pauldrons(root, profile, mat, top):
    for s in (-1, 1):
        ball(f"Pauldron{s}", (s * 0.2, 0, top), 0.092, mat, root, scale=(1.0, 0.8, 0.62))
        ball(f"Lame{s}", (s * 0.235, 0, top - 0.065), 0.078, mat, root, scale=(1.0, 0.8, 0.5))


@item("leather", 18)
def leather_armor(root):
    lth = painted.leather("Leather", "#7a4f2c")
    dark = painted.leather("Dark", "#4e3019")
    body("Cuirass", VEST, lth, root)
    pauldrons(root, VEST, dark, 0.56)
    collar = ri.torus("Collar", (0, 0, 0.625), 0.09, 0.02, dark, root)
    collar.scale = (1.0, 0.7, 1.0)
    # Laced front: a dark slit with cord crossing it.
    bevel(lib.box("Slit", (0.02, 0.01, 0.26), front(VEST, 0, 0.47, 0.0), mat=dark, parent=root), 0.003)
    cord = painted.leather("Lace", "#d2b88a")
    for i in range(5):
        z = 0.37 + i * 0.05
        y = front(VEST, 0, z, 0.006)[1]
        tube(f"Lace{i}a", [(-0.03, y, z - 0.015), (0.03, y, z + 0.015)], 0.0045, cord, root, sides=6)
        tube(f"Lace{i}b", [(-0.03, y, z + 0.015), (0.03, y, z - 0.015)], 0.0045, cord, root, sides=6)
    # A tooled band at the chest and a buckled belt.
    for name, z, h in (("Band", 0.3, 0.018), ("Belt", 0.16, 0.024)):
        b = ri.torus(name, (0, 0, z), radius_at(VEST, z) - 0.004, h, dark, root)
        b.scale = (1.0, 0.58, 1.0)
    bevel(lib.box("Buckle", (0.055, 0.03, 0.055), front(VEST, 0, 0.16, 0.012), mat=painted.gold("Buckle"),
                  parent=root), 0.007)


@item("studded_leather", 18)
def studded_leather(root):
    lth = painted.leather("Leather", "#5e3c22")
    dark = painted.leather("Dark", "#3e2614")
    body("Cuirass", VEST, lth, root)
    pauldrons(root, VEST, dark, 0.56)
    collar = ri.torus("Collar", (0, 0, 0.625), 0.09, 0.02, dark, root)
    collar.scale = (1.0, 0.7, 1.0)
    stud = painted.metal("Stud", "#b8a27a", edge="#fff4d8", rough=0.35, metallic=0.85)
    for row in range(6):
        z = 0.08 + row * 0.075
        for col in range(7):
            x = (col - 3) * 0.052 + (0.026 if row % 2 else 0.0)
            if abs(x) > radius_at(VEST, z) * 0.82:
                continue
            ball(f"Stud{row}_{col}", front(VEST, x, z, -0.001), 0.012, stud, root, scale=(1, 0.6, 1))
    for s in (-1, 1):  # a curve of studs on each pauldron (an ellipsoid: find its front surface)
        for k in range(3):
            dx, dz = s * (k - 1) * 0.04, 0.02 - abs(k - 1) * 0.012
            y = -0.0736 * math.sqrt(max(0.0, 1 - (dx / 0.092) ** 2 - (dz / 0.057) ** 2)) - 0.001
            ball(f"PStud{s}{k}", (s * 0.2 + dx, y, 0.56 + dz), 0.011, stud, root, scale=(1, 0.6, 1))
    b = ri.torus("Belt", (0, 0, 0.04), radius_at(VEST, 0.04) - 0.003, 0.022, dark, root)
    b.scale = (1.0, 0.58, 1.0)


@item("shield", 20)
def shield(root):
    R = 0.32
    tints = ["#6b4a30", "#5e3f28", "#735034", "#62432b", "#6e4c31"]
    n = 5
    for i in range(n):
        x0 = -R + i * 2 * R / n + 0.004
        x1 = -R + (i + 1) * 2 * R / n - 0.004
        p = plank(f"Plank{i}", x0, x1, R - 0.01, 0.035, painted.wood(f"Plank{i}", tints[i], 5.0, along="Z"), root)
        p.location.y = 0.004 * ((i * 7) % 3 - 1)
    # Worn steel rim and boss: pale and scuffed, not blackened iron.
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


def plank(name, x0, x1, radius, thick, mat, parent, steps=10):
    """One board of a round shield: the strip of a disc between x0 and x1."""
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


@item("iron_helm", 22)
def iron_helm(root):
    steel = painted.metal("Helm", "#9ca1a8", rough=0.4, metallic=0.62)
    iron = painted.iron("Bands")
    prof = [(0.001, 0.17), (0.05, 0.165), (0.09, 0.145), (0.115, 0.11), (0.13, 0.06), (0.135, 0.01), (0.137, 0.0)]
    lathe("Dome", prof, steel, root, sides=40)
    lathe("Liner", [(0.128, 0.0), (0.126, -0.018)], painted.leather("Liner", "#4a2c1a"), root, sides=40)
    ri.torus("Brow", (0, 0, 0.012), 0.139, 0.015, iron, root)
    # Spangen: iron bands over the dome from the brow to the crown.
    for a in (-90, 0, 180, 90):
        ar = math.radians(a)
        pts = [(math.cos(ar) * (r + 0.006), math.sin(ar) * (r + 0.006), z) for r, z in reversed(prof[1:])]
        tube(f"Spangen{a}", pts, 0.009, iron, root, sides=6)
        ball(f"BandRivet{a}", (math.cos(ar) * 0.145, math.sin(ar) * 0.145, 0.03), 0.008, iron, root)
    ball("Finial", (0, 0, 0.175), 0.016, iron, root)
    for k in range(14):
        a = math.tau * k / 14 + 0.2
        ball(f"Rivet{k}", (math.cos(a) * 0.152, math.sin(a) * 0.152, 0.012), 0.006, iron, root)
    nasal = [(-0.016, 0.02), (0.016, 0.02), (0.012, -0.08), (0.0, -0.092), (-0.012, -0.08)]
    n = plate("Nasal", nasal, 0.008, iron, root, plane="XZ")
    n.location = (0, -0.152, 0)


def cloak_mesh(n=24):
    verts, faces = [], []
    for j in range(n + 1):
        z = 0.7 * (1 - j / n)
        w = 0.14 + 0.28 * (j / n)
        for i in range(n + 1):
            t = i / n * 2 - 1
            y = 0.04 * math.sin(t * math.pi * 3 + j * 0.2) * (j / n) - 0.05 * (1 - t * t)
            verts.append((t * w, y, z))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    return verts, faces


@item("cloak_of_protection", 15)
def cloak_of_protection(root):
    n = 24
    verts, faces = cloak_mesh(n)
    cl = lib.mesh_object("Cloak", verts, faces, mat=painted.cloth("Cloak", "#2c5a3a", weave=200.0), parent=root,
                         smooth=True)
    cl.modifiers.new("Thick", 'SOLIDIFY').thickness = 0.012
    gold = painted.gold("Trim")
    # Gold trim along the hem and both front edges.
    v = [Vector(p) for p in verts]
    hem = [v[n * (n + 1) + i] + Vector((0, -0.008, 0.008)) for i in range(n + 1)]
    tube("HemTrim", hem, 0.008, gold, root, sides=8)
    for i in (0, n):
        edge = [v[j * (n + 1) + i] + Vector((0, -0.008, 0)) for j in range(n + 1)]
        tube(f"EdgeTrim{i}", edge, 0.007, gold, root, sides=8)
    collar = tube("Collar", [v[i] + Vector((0, -0.012, -0.01)) for i in range(n + 1)], 0.022,
                  painted.cloth("Collar", "#1f4029", weave=200.0), root, sides=12)
    collar.name = "Collar"
    # A gold brooch with a green stone, and a chain across the throat.
    for s in (-1, 1):
        b = ri.cyl(f"Brooch{s}", (s * 0.09, -0.058, 0.665), 0.03, 0.012, gold, root,
                   rot=(math.radians(90), 0, 0), verts=24)
        bevel(b, 0.004, 2)
        ball(f"Stone{s}", (s * 0.09, -0.066, 0.665), 0.016, painted.glow(f"Stone{s}", "#1f8a4a", 0.7, "#b8ffcf"),
             root, scale=(1, 0.6, 1))
    links = 9
    for k in range(links):
        t = k / (links - 1)
        p = Vector((-0.07 + 0.14 * t, -0.064, 0.665 - 0.03 * math.sin(t * math.pi)))
        tangent = Vector((0.14, 0, -0.03 * math.pi * math.cos(t * math.pi))).normalized()
        axis = Vector((0, 1, 0)) if k % 2 else tangent.cross(Vector((0, 1, 0)))
        oriented_torus(f"Link{k}", p, 0.008, 0.0025, gold, root, tangent, axis, stretch=1.4)


@item("ring_of_protection", 30)
def ring_of_protection(root):
    silver = painted.metal("Silver", "#c4c7cc", edge="#ffffff", rough=0.28, metallic=0.85, scratches=False)
    g = group("Ring", root, rot=(math.radians(70), 0, 0))
    ri.torus("Band", (0, 0, 0), 0.1, 0.02, silver, g)
    # The setting sits on top of the band (local +y), facing out.
    lib.cylinder_between("Bezel", (0, 0.105, 0), (0, 0.13, 0), 0.032, 0.036, mat=silver, parent=g, sides=24)
    for k in range(4):
        a = math.tau * k / 4 + math.pi / 4
        tube(f"Prong{k}", [(math.cos(a) * 0.034, 0.128, math.sin(a) * 0.034),
                           (math.cos(a) * 0.03, 0.15, math.sin(a) * 0.03)], 0.006, silver, g, sides=6)
    gem = lib.primitive("ico_sphere", "Gem", mat=painted.glow("Sapphire", "#1f4ad0", 0.8, "#a8c8ff"), parent=g,
                        radius=0.036, subdivisions=1, location=(0, 0.148, 0))
    gem.scale = (1, 0.7, 1)
    for s in (-1, 1):  # shoulders of the band, flaring to hold the setting
        ball(f"Shoulder{s}", (s * 0.03, 0.098, 0), 0.016, silver, g, scale=(1.4, 1, 0.8))


@item("silver_amulet", 12)
def silver_amulet(root):
    silver = painted.metal("Silver", "#c4c7cc", edge="#ffffff", rough=0.3, metallic=0.85, scratches=False)
    gold = painted.gold("Gold")
    d = ri.cyl("Disc", (0, 0, 0), 0.08, 0.015, silver, root, rot=(math.radians(90), 0, 0), verts=40)
    bevel(d, 0.004, 2)
    ri.torus("Rim", (0, -0.003, 0), 0.08, 0.009, silver, root, rot=(math.radians(90), 0, 0))
    for i in range(12):
        a = math.tau * i / 12
        ln = 0.055 if i % 2 == 0 else 0.035
        p = plate(f"Ray{i}", [(math.cos(a - 0.11) * 0.085, math.sin(a - 0.11) * 0.085),
                              (math.cos(a) * (0.085 + ln), math.sin(a) * (0.085 + ln)),
                              (math.cos(a + 0.11) * 0.085, math.sin(a + 0.11) * 0.085)], 0.01, gold, root,
                  plane="XZ", bevel_w=0.002)
        p.name = f"Ray{i}"
    ball("Moonstone", (0, -0.014, 0), 0.032, painted.glow("Moonstone", "#5a8ad8", 0.7, "#e8f2ff"), root,
         scale=(1, 0.45, 1))
    ri.torus("Setting", (0, -0.01, 0), 0.034, 0.006, gold, root, rot=(math.radians(90), 0, 0))
    # A loop of chain hanging from the bail: small links, alternately flat and edge-on.
    links = 30
    for k in range(links):
        th = math.tau * (k + 0.5) / links
        p = Vector((0.16 * math.sin(th), 0, 0.158 + 0.1 * (1 - math.cos(th))))
        tangent = Vector((0.16 * math.cos(th), 0, 0.1 * math.sin(th))).normalized()
        axis = Vector((0, 1, 0)) if k % 2 else tangent.cross(Vector((0, 1, 0)))
        oriented_torus(f"Link{k}", p, 0.011, 0.003, silver, root, tangent, axis, stretch=1.4)
    oriented_torus("Bail", (0, 0, 0.142), 0.016, 0.005, silver, root, (0, 0, 1), (1, 0, 0), stretch=1.2)


def boot(name, x, turn, root):
    leather = painted.leather(name + "Boot", "#5a3a20")
    g = group(name, root, (x, 0, 0), (0, 0, turn))
    lathe(name + "Shaft", [(0.056, 0.31), (0.058, 0.25), (0.054, 0.16), (0.05, 0.09), (0.056, 0.03)], leather, g)
    cuff = ri.torus(name + "Cuff", (0, 0, 0.315), 0.06, 0.017, painted.leather(name + "Cuff", "#7a5232"), g)
    cuff.scale = (1.0, 1.0, 1.6)
    ball(name + "Foot", (0, -0.07, 0.045), 0.06, leather, g, scale=(0.85, 1.9, 0.8))
    sole = painted.leather(name + "Sole", "#2a1a10")
    bevel(lib.box(name + "Sole", (0.106, 0.25, 0.022), (0, -0.068, 0.008), mat=sole, parent=g), 0.01)
    bevel(lib.box(name + "Heel", (0.092, 0.07, 0.035), (0, 0.03, 0.016), mat=sole, parent=g), 0.008)
    strap = ri.torus(name + "Strap", (0, -0.004, 0.12), 0.057, 0.008, painted.leather(name + "Strap", "#3a2414"), g)
    strap.scale = (1.0, 1.05, 1.0)
    bevel(lib.box(name + "Buckle", (0.03, 0.012, 0.03), (0.0, -0.064, 0.12), mat=painted.gold(name + "Buckle"),
                  parent=g), 0.004)


@item("leather_boots", 22)
def leather_boots(root):
    boot("L", -0.075, 0.1, root)
    boot("R", 0.085, -0.05, root)
    root.rotation_euler = (0, 0, math.radians(20))


def glove(name, x, angle, root):
    mat = painted.leather(name + "Glove", "#6b4528")
    g = group(name, root, (x, 0, 0), (0, 0, angle))
    bevel(lib.box(name + "Palm", (0.095, 0.105, 0.03), (0, 0, 0.016), mat=mat, parent=g), 0.013)
    for i, (fx, fl) in enumerate(((-0.034, 0.068), (-0.011, 0.084), (0.012, 0.08), (0.034, 0.064))):
        tube(f"{name}F{i}", [(fx, 0.045, 0.018), (fx, 0.05 + fl * 0.6, 0.02), (fx * 1.05, 0.05 + fl, 0.014)],
             [0.0115, 0.011, 0.0095], mat, g, sides=10)
    tube(name + "Thumb", [(0.045, 0.0, 0.016), (0.07, 0.025, 0.017), (0.088, 0.055, 0.014)], [0.013, 0.012, 0.0105],
         mat, g, sides=10)
    cuff = painted.leather(name + "Cuff", "#7a5232")
    bevel(lib.box(name + "Cuff", (0.118, 0.085, 0.036), (0, -0.095, 0.02), mat=cuff, parent=g), 0.014)
    bevel(lib.box(name + "Strap", (0.12, 0.018, 0.04), (0, -0.065, 0.022), mat=painted.leather(name + "S", "#3a2414"),
                  parent=g), 0.004)
    bevel(lib.box(name + "Buckle", (0.025, 0.024, 0.044), (0.03, -0.065, 0.026), mat=painted.gold(name + "B"),
                  parent=g), 0.004)


@item("leather_gloves", 65)
def leather_gloves(root):
    glove("L", -0.07, math.radians(20), root)
    glove("R", 0.08, math.radians(-15), root)


# --------------------------------------------------------------------------
# Potions
# --------------------------------------------------------------------------

@item("potion_of_healing", 22)
def potion_of_healing(root):
    """A bulbous flask in a brass cage, glowing red."""
    prof = [(0.001, 0.0), (0.06, 0.004), (0.075, 0.02), (0.11, 0.06), (0.125, 0.11), (0.115, 0.16), (0.08, 0.2),
            (0.04, 0.225), (0.032, 0.25), (0.032, 0.29), (0.042, 0.3)]
    lathe("Flask", prof, painted.glass("Glass"), root, sides=40)
    inner = [(0.001, 0.008), (0.07, 0.014), (0.105, 0.06), (0.117, 0.1), (0.116, 0.125), (0.001, 0.125)]
    lathe("Liquid", inner, painted.glow("Liquid", "#9a0e16", 1.1, "#ff6a4a"), root, sides=40)
    ball("Bubble1", (0.03, -0.06, 0.09), 0.012, painted.glass("Bubble"), root)
    ball("Bubble2", (-0.04, -0.07, 0.06), 0.008, painted.glass("Bubble2"), root)
    gold = painted.gold("Cage")
    for z, r, th in ((0.012, 0.072, 0.012), (0.11, 0.128, 0.011), (0.2, 0.085, 0.01), (0.255, 0.036, 0.012)):
        ri.torus(f"Band{z}", (0, 0, z), r, th, gold, root)
    for k in range(6):
        a = 2 * math.pi * k / 6
        pts = [(math.cos(a) * (r + 0.004), math.sin(a) * (r + 0.004), z)
               for r, z in ((0.072, 0.012), (0.105, 0.05), (0.124, 0.11), (0.115, 0.16), (0.085, 0.2))]
        tube(f"Strap{k}", pts, 0.006, gold, root, sides=8)
        ball(f"Stud{k}", (math.cos(a) * 0.136, math.sin(a) * 0.136, 0.11), 0.013, gold, root)
    cork_and_seal(root, 0.29, 0.03, "#8a1a14")


def cork_and_seal(root, z, r, wax_color):
    ri.cyl("Cork", (0, 0, z + 0.025), r, 0.05, painted.wood("Cork", "#b58a55", 12.0, along="Z"), root, verts=20)
    ball("Seal", (0, 0, z + 0.052), r * 1.2, painted.leather("Wax", wax_color), root, scale=(1, 1, 0.45))
    cord = painted.leather("Cord", "#c8b07a")
    loop = [(r + 0.004 + 0.05 * math.sin(t / 10 * math.pi), -0.01, z - 0.02 - 0.09 * math.sin(t / 20 * math.pi))
            for t in range(11)]
    tube("Cord", loop, 0.005, cord, root, sides=6)


@item("potion_of_greater_healing", 22)
def potion_of_greater_healing(root):
    """A cut-crystal flask in a red leather harness, glowing violet."""
    prof = [(0.001, 0.0), (0.05, 0.01), (0.1, 0.07), (0.112, 0.12), (0.085, 0.19), (0.036, 0.235), (0.03, 0.26),
            (0.03, 0.29), (0.038, 0.3)]
    lathe("Flask", prof, painted.glass("Crystal"), root, sides=8, flat=True)
    inner = [(0.001, 0.012), (0.045, 0.018), (0.09, 0.07), (0.1, 0.12), (0.082, 0.165), (0.001, 0.165)]
    lathe("Liquid", inner, painted.glow("Liquid", "#5a1478", 1.2, "#e08aff"), root, sides=8, flat=True)
    harness = painted.leather("Harness", "#8a2a24")
    gold = painted.gold("Fittings")
    for k in range(4):
        a = 2 * math.pi * (k + 0.5) / 8 * 2
        pts = [(math.cos(a) * (r + 0.006), math.sin(a) * (r + 0.006), z)
               for r, z in ((0.05, 0.01), (0.1, 0.07), (0.112, 0.12), (0.085, 0.19), (0.04, 0.23))]
        tube(f"Strap{k}", pts, [0.012, 0.014, 0.014, 0.012, 0.01], harness, root, sides=4)
        ball(f"Rivet{k}", (math.cos(a) * 0.126, math.sin(a) * 0.126, 0.12), 0.011, gold, root)
    band = ri.torus("Band", (0, 0, 0.12), 0.116, 0.013, harness, root)
    band.scale = (1, 1, 1.4)
    ri.torus("Collar", (0, 0, 0.255), 0.036, 0.01, gold, root)
    lib.cylinder_between("Point", (0, 0, 0.012), (0, 0, -0.035), 0.03, 0.004, mat=gold, parent=root, sides=8)
    cap = ri.cyl("Cap", (0, 0, 0.31), 0.044, 0.04, gold, root, verts=8)
    bevel(cap, 0.005, 2)
    ball("CapGem", (0, -0.044, 0.31), 0.012, painted.glow("CapGem", "#b0141a", 0.6, "#ff9a7a"), root,
         scale=(1, 0.6, 1))


@item("remedy", 22)
def remedy(root):
    """A gourd-shaped flask of green draught, corked and sealed, with a paper
    label tied round its neck."""
    prof = [(0.001, 0.0), (0.06, 0.004), (0.09, 0.03), (0.098, 0.07), (0.08, 0.11), (0.058, 0.13), (0.066, 0.16),
            (0.064, 0.19), (0.04, 0.22), (0.026, 0.24), (0.026, 0.28), (0.034, 0.29)]
    lathe("Flask", prof, painted.glass("Glass", "#e2f0e0"), root, sides=40)
    inner = [(0.001, 0.008), (0.055, 0.012), (0.082, 0.035), (0.09, 0.07), (0.074, 0.105), (0.052, 0.125),
             (0.058, 0.15), (0.001, 0.15)]
    lathe("Liquid", inner, painted.glow("Draught", "#2a6a1e", 0.8, "#a8e070"), root, sides=40)
    ball("Bubble", (0.03, -0.055, 0.08), 0.01, painted.glass("Bubble"), root)
    cork_and_seal(root, 0.28, 0.024, "#2a4a1a")
    twine = painted.leather("Twine", "#8a6a3a")
    ri.torus("Twine", (0, 0, 0.235), 0.03, 0.005, twine, root)
    tube("TagString", [(0.0, -0.03, 0.235), (0.02, -0.06, 0.2), (0.03, -0.075, 0.16)], 0.003, twine, root, sides=6)
    tag = bevel(lib.box("Tag", (0.06, 0.004, 0.042), (0.035, -0.08, 0.135), mat=painted.pages("Tag", "#e8dcc0"),
                        parent=root, rotation=(0, math.radians(-10), 0)), 0.003)
    tag.name = "Tag"
    ri.torus("Belly", (0, 0, 0.07), 0.1, 0.006, painted.gold("Band"), root)


# --------------------------------------------------------------------------
# Food and gear
# --------------------------------------------------------------------------

@item("rations", 45)
def rations(root):
    parcel = painted.cloth("Wrap", "#a89878", weave=160.0)
    bevel(lib.box("Parcel", (0.24, 0.16, 0.08), (0.05, 0.05, 0.04), mat=parcel, parent=root), 0.025)
    twine = painted.leather("Twine", "#5a4a30")
    for name, size in (("TwineA", (0.014, 0.168, 0.086)), ("TwineB", (0.248, 0.014, 0.086))):
        bevel(lib.box(name, size, (0.05, 0.05, 0.04), mat=twine, parent=root), 0.004)
    ball("Knot", (0.05, 0.05, 0.085), 0.012, twine, root)
    crust = painted.leather("Crust", "#b07a3a")
    ball("Bread", (-0.1, -0.06, 0.05), 0.08, crust, root, scale=(1.3, 0.9, 0.65))
    flour = painted.leather("Score", "#e2c48a")
    for k in range(3):
        bevel(lib.box(f"Score{k}", (0.012, 0.07, 0.01), (-0.14 + k * 0.04, -0.06, 0.1), mat=flour, parent=root,
                      rotation=(0, 0, math.radians(30))), 0.003)
    cheese = painted.leather("Cheese", "#e0b84a")
    w = lib.mesh_object("Cheese", [(0.05, -0.12, 0), (0.17, -0.1, 0), (0.1, -0.03, 0),
                                   (0.05, -0.12, 0.06), (0.17, -0.1, 0.06), (0.1, -0.03, 0.06)],
                        [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)], mat=cheese, parent=root)
    fix_normals(w)
    bevel(w, 0.006, 2)
    sausage = painted.leather("Sausage", "#7a2e22")
    tube("Sausage", [(0.2, 0.0, 0.03), (0.22, -0.05, 0.03), (0.2, -0.1, 0.03), (0.16, -0.14, 0.03)], 0.026, sausage,
         root, sides=14)


@item("apple", 30)
def apple(root):
    prof = [(0.001, 0.012), (0.045, 0.0), (0.085, 0.025), (0.108, 0.075), (0.106, 0.13), (0.085, 0.17),
            (0.045, 0.188), (0.016, 0.176), (0.001, 0.168)]
    lathe("Apple", prof, painted.fruit("Apple", "#a8231a", "#d8a83a"), root, sides=40)
    stem = painted.wood("Stem", "#4a3020", 20.0, along="Z")
    tube("Stem", [(0, 0, 0.17), (0.004, 0.002, 0.2), (0.014, 0.006, 0.228)], [0.007, 0.006, 0.005], stem, root,
         sides=8)
    leaf = painted.leather("Leaf", "#4a7a2a")
    p = plate("Leaf", [(0.0, 0.0), (0.03, 0.02), (0.07, 0.024), (0.1, 0.0), (0.07, -0.016), (0.03, -0.016)], 0.003,
              leaf, root, bevel_w=0.0)
    p.location = (0.012, 0.004, 0.215)
    p.rotation_euler = (math.radians(12), math.radians(-20), math.radians(-25))
    vein = painted.leather("Vein", "#8aa84a")
    tube("Vein", [(0.0, 0.0, 0.002), (0.095, 0.0, 0.002)], 0.0015, vein, p, sides=4)


@item("torch", 70)
def torch(root):
    stick = painted.wood("Stick", "#6a4a2a", 6.0, along="X")
    lib.cylinder_between("Stick", (-0.32, 0, 0), (0.2, 0, 0), 0.02, 0.025, mat=stick, parent=root, sides=14)
    iron = painted.iron("Bands")
    for x in (0.1, 0.13):
        ring_x(f"Band{x}", x, 0.027, 0.006, iron, root)
    rag = painted.cloth("Rag", "#3a2e22", weave=120.0)
    for i in range(5):
        x = 0.14 + i * 0.025
        t = ri.torus(f"Rag{i}", (x, 0, 0), 0.036 - i * 0.002, 0.016, rag, root,
                     rot=(math.radians(8 * (i % 2 * 2 - 1)), math.radians(90), 0))
        t.scale = (1.0, 1.0, 1.4)
    ball("Pitch", (0.27, 0, 0), 0.036, painted.leather("Pitch", "#1e1610"), root, scale=(0.9, 1, 1))
    # The flame rises up the picture (world +y), not along the stick, so turn it
    # back by the 40 degrees the whole torch is turned.
    # A teardrop flame rising up the picture (world +y), not along the stick:
    # the group turns the flame's own +z to "up" undoing the torch's 40 degree
    # turn. It glows only gently, in strong orange with a yellow heart, since
    # bright light loses its colour through AgX (see the docs).
    g = group("FlameAt", root, (0.285, 0.02, 0.012), (math.radians(-90), 0, math.radians(-40)))
    tongue = [(0.001, 0.0), (0.034, 0.012), (0.05, 0.045), (0.046, 0.085), (0.032, 0.13), (0.015, 0.175),
              (0.001, 0.205)]
    o = lathe("Flame", tongue, painted.glow("Flame", "#ff4a00", 1.1, "#ff9a10", gloss=False), g, sides=24)
    o.scale = (1.0, 0.7, 1.0)
    h = lathe("Heart", [(r * 0.55, z * 0.6 + 0.008) for r, z in tongue],
              painted.glow("Heart", "#ffc020", 1.5, "#fff0a0", gloss=False), g, sides=24)
    h.scale = (1.0, 0.7, 1.0)
    h.location.y = -0.012  # in front of the outer flame, towards the camera
    ri.diagonal(root, 40)


@item("lantern", 20)
def lantern(root):
    brass = painted.gold("Brass")
    bevel(lib.box("Base", (0.15, 0.15, 0.03), (0, 0, 0.015), mat=brass, parent=root), 0.006)
    bevel(lib.box("Top", (0.15, 0.15, 0.025), (0, 0, 0.205), mat=brass, parent=root), 0.006)
    hood = lib.mesh_object("Hood", [(-0.075, -0.075, 0.217), (0.075, -0.075, 0.217), (0.075, 0.075, 0.217),
                                    (-0.075, 0.075, 0.217), (0, 0, 0.27)],
                           [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], mat=brass, parent=root)
    hood.modifiers.new("T", 'SOLIDIFY').thickness = 0.006
    ri.cyl("Vent", (0, 0, 0.275), 0.022, 0.03, brass, root, verts=16)
    ball("VentCap", (0, 0, 0.295), 0.026, brass, root, scale=(1, 1, 0.5))
    for sx in (-1, 1):
        for sy in (-1, 1):
            bevel(lib.box(f"Post{sx}{sy}", (0.016, 0.016, 0.18), (sx * 0.067, sy * 0.067, 0.11), mat=brass,
                          parent=root), 0.003)
    for z in (0.07, 0.15):  # cross bars on the panes
        bevel(lib.box(f"Bar{z}", (0.14, 0.008, 0.008), (0, -0.068, z), mat=brass, parent=root), 0.002)
    lib.box("Glass", (0.125, 0.125, 0.17), (0, 0, 0.11), mat=painted.glass("LGlass", "#f4e8c8"), parent=root)
    candle = painted.cloth("Candle", "#e8dcc0", weave=60.0)
    ri.cyl("Candle", (0, 0, 0.06), 0.02, 0.06, candle, root, verts=16)
    flame = painted.glow("Flame", "#f09030", 6.0, "#fff4c0")
    ball("Flame", (0, 0, 0.115), 0.018, flame, root, scale=(1, 1, 1.9))
    light = bpy.data.lights.new("Glow", 'POINT')
    light.energy = 2.0
    light.color = (1.0, 0.7, 0.35)
    light.shadow_soft_size = 0.02
    lo = bpy.data.objects.new("Glow", light)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = (0, 0, 0.115)
    ri.torus("Handle", (0, 0, 0.33), 0.045, 0.007, brass, root, rot=(math.radians(90), 0, 0))
    ri.torus("Loop", (0, 0, 0.3), 0.012, 0.005, brass, root)


@item("holy_symbol", 12)
def holy_symbol(root):
    gold = painted.gold("Gold")
    d = ri.cyl("Disc", (0, 0, 0), 0.07, 0.02, gold, root, rot=(math.radians(90), 0, 0), verts=32)
    bevel(d, 0.005, 2)
    ri.torus("Ring", (0, -0.006, 0), 0.07, 0.008, gold, root, rot=(math.radians(90), 0, 0))
    for i in range(16):
        a = math.tau * i / 16
        ln = 0.075 if i % 2 == 0 else 0.045
        plate(f"Ray{i}", [(math.cos(a - 0.12) * 0.072, math.sin(a - 0.12) * 0.072),
                          (math.cos(a) * (0.072 + ln), math.sin(a) * (0.072 + ln)),
                          (math.cos(a + 0.12) * 0.072, math.sin(a + 0.12) * 0.072)], 0.012, gold, root, plane="XZ",
              bevel_w=0.002)
    ball("Ruby", (0, -0.014, 0), 0.032, painted.glow("Ruby", "#a8141a", 0.8, "#ff8a6a"), root, scale=(1, 0.5, 1))
    ri.torus("Setting", (0, -0.012, 0), 0.034, 0.006, gold, root, rot=(math.radians(90), 0, 0))
    oriented_torus("Bail", (0, 0, 0.158), 0.014, 0.005, gold, root, (0, 0, 1), (1, 0, 0), stretch=1.2)
    cord = painted.leather("Cord", "#3b2616")
    tube("Cord", [(-0.06, 0, 0.29), (-0.03, 0, 0.21), (0, 0, 0.17), (0.03, 0, 0.21), (0.06, 0, 0.29)], 0.006, cord,
         root, sides=8)


@item("thieves_tools", 60)
def thieves_tools(root):
    roll = painted.leather("Roll", "#5a3a22")
    bevel(lib.box("Roll", (0.38, 0.22, 0.012), (0, 0, 0.006), mat=roll, parent=root), 0.01)
    pocket = painted.leather("Pocket", "#4a3020")
    bevel(lib.box("Pocket", (0.38, 0.07, 0.016), (0, -0.075, 0.016), mat=pocket, parent=root), 0.006)
    for k in range(7):  # stitched dividers between the pockets
        bevel(lib.box(f"Seam{k}", (0.004, 0.068, 0.004), (-0.15 + k * 0.05, -0.075, 0.025), mat=roll, parent=root),
              0.001)
    steel = painted.metal("Picks", "#b4b8be", rough=0.32)
    handle = painted.wood("Handles", "#3a2818", 10.0, along="Y")
    tips = ((0.0, 0.0), (0.012, 0.012), (-0.01, 0.0), (0.0, -0.012), (0.014, 0.0), (0.0, 0.0))
    for i, (bend, hook) in enumerate(tips):
        x = -0.125 + i * 0.05
        tube(f"Pick{i}", [(x, -0.06, 0.02), (x, 0.03, 0.02), (x + bend, 0.07, 0.02), (x + bend + hook, 0.085, 0.02)],
             0.0045, steel, root, sides=6)
        tube(f"Handle{i}", [(x, -0.105, 0.022), (x, -0.06, 0.022)], [0.01, 0.009], handle, root, sides=10)
        ring_y = ri.torus(f"Ferrule{i}", (x, -0.06, 0.022), 0.0095, 0.003, steel, root,
                          rot=(math.radians(90), 0, 0))
        ring_y.name = f"Ferrule{i}"
    strap = painted.leather("Strap", "#3a2414")
    bevel(lib.box("Strap", (0.03, 0.26, 0.008), (0.2, 0, 0.018), mat=strap, parent=root), 0.003)
    bevel(lib.box("Buckle", (0.04, 0.03, 0.012), (0.2, -0.07, 0.024), mat=painted.gold("Buckle"), parent=root), 0.003)
    root.rotation_euler = (0, 0, math.radians(20))


@item("spellbook", 50)
def spellbook(root):
    cover = painted.leather("Cover", "#4a2a5a")
    bevel(lib.box("Cover", (0.24, 0.32, 0.075), (0, 0, 0.0375), mat=cover, parent=root), 0.012)
    bevel(lib.box("Pages", (0.226, 0.304, 0.056), (0.012, 0, 0.0375), mat=painted.pages("Pages"), parent=root),
          0.003)
    spine = ri.cyl("Spine", (-0.118, 0, 0.0375), 0.04, 0.32, cover, root, rot=(math.radians(90), 0, 0), verts=24)
    spine.scale = (0.35, 1.0, 1.0)
    gold = painted.gold("Gold")
    for s in (-1, 1):  # raised bands across the spine
        for k in (-1, 0, 1):
            ri.torus(f"SpineBand{s}{k}", (-0.12, k * 0.09, 0.0375), 0.015, 0.004, gold, root,
                     rot=(math.radians(90), 0, 0)).scale = (0.9, 1.0, 2.2)
    for sx, sy in ((1, 1), (1, -1)):
        p = plate(f"Corner{sy}", [(0.12 * sx, 0.16 * sy), (0.06 * sx, 0.16 * sy), (0.12 * sx, 0.1 * sy)], 0.008, gold,
                  root, bevel_w=0.002)
        p.location.z = 0.077
    ri.torus("Sigil", (0.01, 0, 0.077), 0.055, 0.006, gold, root)
    for k in range(6):
        a = math.tau * k / 6
        ball(f"Star{k}", (0.01 + math.cos(a) * 0.055, math.sin(a) * 0.055, 0.079), 0.008, gold, root)
    ball("Eye", (0.01, 0, 0.08), 0.022, painted.glow("Eye", "#3a8ad8", 0.9, "#c8f0ff"), root, scale=(1, 1, 0.5))
    bevel(lib.box("ClaspStrap", (0.05, 0.04, 0.079), (0.11, 0, 0.0395), mat=painted.leather("Strap", "#2e1a38"),
                  parent=root), 0.004)
    bevel(lib.box("Clasp", (0.03, 0.05, 0.03), (0.13, 0, 0.0395), mat=gold, parent=root), 0.005)
    ribbon = painted.cloth("Ribbon", "#a8241e", weave=300.0)
    plate("Ribbon", [(0.04, -0.152), (0.055, -0.152), (0.06, -0.22), (0.048, -0.208), (0.036, -0.218)], 0.003,
          ribbon, root, bevel_w=0.0).location.z = 0.03
    root.rotation_euler = (0, 0, math.radians(-25))


@item("garnet", 35)
def garnet(root):
    """A round brilliant-cut stone: a flat table, crown facets, a pointed pavilion."""
    table, girdle = 8, 16
    verts = [(math.cos(math.tau * i / table) * 0.045, math.sin(math.tau * i / table) * 0.045, 0.075)
             for i in range(table)]
    verts += [(math.cos(math.tau * i / girdle) * 0.085, math.sin(math.tau * i / girdle) * 0.085, 0.04)
              for i in range(girdle)]
    verts += [(math.cos(math.tau * i / girdle) * 0.085, math.sin(math.tau * i / girdle) * 0.085, 0.03)
              for i in range(girdle)]
    verts.append((0, 0, -0.035))
    faces = [tuple(range(table))]
    for i in range(table):
        t0, t1 = i, (i + 1) % table
        g0, g1, g2 = table + 2 * i, table + 2 * i + 1, table + (2 * i + 2) % girdle
        faces += [(t0, g0, g1), (t0, g1, t1), (t1, g1, g2)]
    for i in range(girdle):
        a, b = table + i, table + (i + 1) % girdle
        faces.append((a, b, b + girdle, a + girdle))
        faces.append((a + girdle, b + girdle, len(verts) - 1))
    gem = fix_normals(lib.mesh_object("Garnet", verts, faces, mat=painted.glow("Garnet", "#7a0a14", 0.7, "#ff5a4a"),
                                      parent=root))
    gem.rotation_euler = (math.radians(-22), 0, math.radians(10))


@item("key", 75)
def key(root):
    iron = painted.metal("Key", "#86817a", edge="#e8e0d0", rough=0.48, metallic=0.75)
    ri.torus("Bow", (-0.13, 0, 0), 0.05, 0.012, iron, root)
    for k in range(4):  # a quatrefoil inside the bow
        a = math.tau * k / 4
        ri.torus(f"Foil{k}", (-0.13 + math.cos(a) * 0.018, math.sin(a) * 0.018, 0), 0.017, 0.005, iron, root)
    tube("Shank", [(-0.08, 0, 0), (0.16, 0, 0)], 0.011, iron, root, sides=12)
    for x in (-0.07, -0.05, 0.06):
        ring_x(f"Collar{x}", x, 0.013, 0.005, iron, root)
    bevel(lib.box("Bit", (0.06, 0.055, 0.016), (0.13, -0.035, 0), mat=iron, parent=root), 0.003)
    for k, (x, d) in enumerate(((0.11, 0.022), (0.135, 0.012), (0.155, 0.026))):
        bevel(lib.box(f"Ward{k}", (0.012, d, 0.017), (x, -0.062 - d / 2 + 0.004, 0), mat=iron, parent=root), 0.002)
    ball("Tip", (0.165, 0, 0), 0.013, iron, root)
    ri.diagonal(root, 40)


@item("gold", 45)
def gold(root):
    mat = painted.metal("Coins", "#c8962e", edge="#fff0b0", rough=0.3, metallic=0.85, scratches=False)
    r = np.random.default_rng(5)
    k = 0

    def coin(loc, rot):
        nonlocal k
        g = group(f"Coin{k}", root, loc, rot)
        c = ri.cyl(f"CoinBody{k}", (0, 0, 0), 0.03, 0.006, mat, g, verts=24)
        bevel(c, 0.0015, 1)
        ri.torus(f"CoinRim{k}", (0, 0, 0.003), 0.027, 0.0022, mat, g)
        ri.cyl(f"CoinFace{k}", (0, 0, 0.003), 0.012, 0.002, mat, g, verts=12)
        k += 1

    for layer, count in ((0, 14), (1, 8), (2, 4)):
        for _ in range(count):
            ang = r.uniform(0, math.tau)
            rad = r.uniform(0, 0.11 - layer * 0.03)
            coin((math.cos(ang) * rad, math.sin(ang) * rad, 0.006 + layer * 0.012 + r.uniform(0, 0.004)),
                 (r.uniform(-0.25, 0.25), r.uniform(-0.25, 0.25), r.uniform(0, math.tau)))
    for h in range(5):  # a little stack beside the pile
        coin((0.12, -0.05, 0.004 + h * 0.0075), (0, 0, r.uniform(0, math.tau)))


def spiral_roll(name, x0, x1, r_out, turns, thick, mat, parent):
    """Parchment rolled up along X: an Archimedean spiral (radius growing
    steadily with angle) swept from x0 to x1, so the ends show the turns of
    the sheet. The outer edge finishes at the bottom, heading towards -Y,
    where the unrolled tongue carries on."""
    n = int(turns * 32)
    pts = []
    for k in range(n + 1):
        t = k / n
        a = 1.5 * math.pi - (1 - t) * turns * 2 * math.pi  # ends at 3/2 pi: straight down
        r = r_out * (0.2 + 0.8 * t)
        pts.append((-r * math.cos(a), r * math.sin(a)))  # mirrored in Y so it unrolls towards -Y
    verts = [(x0, y, z) for y, z in pts] + [(x1, y, z) for y, z in pts]
    faces = [(k, k + 1, n + 2 + k, n + 1 + k) for k in range(n)]
    obj = lib.mesh_object(name, verts, faces, mat=mat, parent=parent, smooth=True)
    sol = obj.modifiers.new("Thick", 'SOLIDIFY')
    sol.thickness = thick
    return obj


def scroll(root, ribbon_color, seal_color, rune_color):
    """A spell scroll: a parchment roll with a tongue unrolled towards the
    viewer, inked lines and a glowing rune on it, tied with a ribbon and
    sealed with wax. Ribbon, seal and rune are in the spell's colours."""
    parchment = painted.leather("Parchment", "#ead8a8")
    r = 0.045
    spiral_roll("Roll", -0.2, 0.2, r, 3.75, 0.004, parchment, root)
    plate("Sheet", [(-0.2, 0.0), (0.2, 0.0), (0.2, -0.17), (0.07, -0.18), (-0.06, -0.165), (-0.2, -0.175)], 0.004,
          parchment, root, bevel_w=0.0).location.z = -r
    ink = painted.leather("Ink", "#2e2014")
    for i, w in enumerate((0.15, 0.12, 0.14, 0.08)):
        x = -0.17
        plate(f"Line{i}", [(x, 0), (x + w, 0), (x + w, -0.008), (x, -0.008)], 0.001, ink, root,
              bevel_w=0.0).location = (0, -0.05 - i * 0.03, -r + 0.0025)
    rune = painted.glow("Rune", rune_color, 4.0, "#fff6e0", gloss=False)
    ri.torus("Rune", (0.1, -0.1, -r + 0.003), 0.032, 0.006, rune, root).scale = (1, 1, 0.4)
    for k in range(3):
        a = math.tau * k / 3 + 0.5
        tube(f"RuneStroke{k}", [(0.1 + math.cos(a) * 0.026, -0.1 + math.sin(a) * 0.026, -r + 0.003),
                                (0.1 - math.cos(a) * 0.01, -0.1 - math.sin(a) * 0.01, -r + 0.003)],
             0.0045, rune, root, sides=6)
    ribbon = painted.cloth("Ribbon", ribbon_color, weave=300.0)
    ring_x("Band", 0.03, r + 0.003, 0.006, ribbon, root).scale = (1.0, 1.0, 1.6)
    for k, (dx, ang) in enumerate(((-0.014, -0.25), (0.016, 0.3))):
        tail = plate(f"Tail{k}", [(-0.008, 0), (0.008, 0), (0.01, -0.1), (0.0, -0.088), (-0.01, -0.1)], 0.003,
                     ribbon, root, bevel_w=0.0)
        tail.location = (0.03 + dx, -0.02, -r + 0.004)
        tail.rotation_euler = (0, 0, ang)
    wax = painted.leather("Wax", seal_color)
    ball("Seal", (0.03, -0.05, -r + 0.01), 0.03, wax, root, scale=(1, 1, 0.35))
    ri.torus("SealRim", (0.03, -0.05, -r + 0.019), 0.017, 0.003, wax, root)
    ball("SealBoss", (0.03, -0.05, -r + 0.019), 0.008, wax, root, scale=(1, 1, 0.5))
    root.rotation_euler = (0, 0, math.radians(25))


@item("scroll_of_cure_wounds", 55)
def scroll_of_cure_wounds(root):
    scroll(root, "#3a8a48", "#b8242a", "#60e080")


@item("scroll_of_magic_missile", 55)
def scroll_of_magic_missile(root):
    scroll(root, "#5a3aa0", "#2a4ab0", "#a080ff")


@item("scroll_of_burning_hands", 55)
def scroll_of_burning_hands(root):
    scroll(root, "#c0501a", "#7a1410", "#ff8a2a")


# --------------------------------------------------------------------------

def build(name):
    """Sets up the scene and builds one item's model. Returns its camera elevation."""
    fn, elevation = ALL[name]
    root = scene()
    fn(root)
    return elevation


def run(names=None):
    for name in names or ALL:
        elevation = build(name)
        render_icon(name, elevation)
