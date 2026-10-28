"""Window frames for the HUD, pre-rendered like the rest of the art.

frame_gold.png: an ornate gilded frame for the inventory screen. A moulding
runs round all four sides (an outer bead, a cove, a rounded top and an inner
bead). Each corner has a rosette with an amber stone on a four-lobed plate,
scrolls curling along both edges with leaves off them, and a leaf finial
pointing out of the corner. It is rendered top down, then composited in PIL
over the panel's dark background with an inner shadow, a fine gilt rule just
inside the moulding and a drop shadow outside.

The game draws it as a 9-slice (StyleBoxTexture, UiTheme.ornate_frame): the
CORNER-pixel corners keep their ornaments and the straight moulding between
them stretches, so everything ornate has to stay inside the corners.

frame_gold_crest_<side>.png: the ornament for the middle of each side (an
oval medallion with scrolls either way and a crowning leaf pointing out),
drawn by UiTheme.draw_frame_crests over the moulding at the mid-points. One
picture per side, so the light comes from the same place on all four.

Output: assets/ui/, rendered at twice the size and shrunk.
"""
import math

import bpy
import numpy as np
from mathutils import Vector
from PIL import Image, ImageDraw, ImageFilter

import lib
import painted
import render_items as ri
import render_items_painted as rp

SIZE = 760        # frame texture, pixels (square)
OUT = 30          # transparent margin outside the moulding (finials, shadow); UiTheme.FRAME_OUTSET
BAND = 26         # moulding width
CORNER = 150      # 9-slice margin: ornaments stay inside this; UiTheme.FRAME_CORNER
CREST = (200, 84)  # top crest; its moulding centre line runs CREST_LINE px from its outer (top) edge
CREST_LINE = 46
# side -> turn (radians, Blender's anticlockwise) from the top crest
CREST_SIDES = {"top": 0.0, "right": -math.pi / 2, "bottom": math.pi, "left": math.pi / 2}
U = 0.01          # Blender units per final pixel
SAMPLES = 96
BG = (0x1c, 0x18, 0x14)
RULE = (0x8a, 0x6e, 0x40)


# --------------------------------------------------------------------------
# Scene and materials
# --------------------------------------------------------------------------

def scene(width_px, height_px):
    """Lights, an orthographic camera looking straight down at a frame of
    width_px x height_px final pixels centred on the origin, and a root."""
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=(0.5, 0.44, 0.36), sky_strength=0.6)
    bpy.context.scene.cycles.max_bounces = 6
    # Suns rather than area lights: the same light all along a long frame.
    for name, direction, energy, color in (
            ("Key", (-1.0, 1.1, 1.3), 4.6, (1.0, 0.92, 0.78)),
            ("Fill", (1.2, -0.8, 1.0), 1.2, (1.0, 0.84, 0.64)),
            ("Rim", (0.6, 1.0, 0.5), 1.0, (0.72, 0.82, 1.0))):
        data = bpy.data.lights.new(name, 'SUN')
        data.energy = energy
        data.color = color
        data.angle = math.radians(8)
        obj = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(obj)
        obj.rotation_euler = Vector(direction).to_track_quat('Z', 'Y').to_euler()
    vs = bpy.context.scene.view_settings
    vs.view_transform = 'AgX'
    vs.look = 'AgX - Punchy'
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = max(width_px, height_px) * U
    cam_data.clip_end = 50
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = (0, 0, 10)
    bpy.context.scene.camera = cam
    r = bpy.context.scene.render
    r.resolution_x = width_px * 2
    r.resolution_y = height_px * 2
    r.resolution_percentage = 100
    root = bpy.data.objects.new("Frame", None)
    bpy.context.scene.collection.objects.link(root)
    return root


def materials():
    gold = painted.metal("Gold", "#c49a3e", edge="#fff2c4", rough=0.3, metallic=0.95, scratches=False)
    stone = painted.glow("Amber", "#a8420a", 1.0, "#ffc468")
    return gold, stone


# --------------------------------------------------------------------------
# The moulding
# --------------------------------------------------------------------------

def profile():
    """(inset from the outer edge, height) in pixels, outside to inside."""
    pts = [(0.0, 0.0)]
    for k in range(13):  # outer half-round bead
        t = math.pi * (1 - k / 12)
        pts.append((4.5 + 4.5 * math.cos(t), 2.0 + 4.5 * math.sin(t)))
    pts.append((9.6, 1.6))
    for k in range(1, 9):  # cove rising to the top
        u = k / 8
        pts.append((10.0 + 5.0 * u, 1.6 + 3.6 * (1 - math.sqrt(max(0.0, 1 - u * u)))))
    for k in range(1, 9):  # rounded top
        pts.append((15.0 + 5.0 * k / 8, 5.2 + 1.1 * math.sin(math.pi * k / 8)))
    pts.append((20.4, 1.6))
    for k in range(1, 12):  # inner bead
        t = math.pi * (1 - k / 11)
        pts.append((23.0 + 2.5 * math.cos(t), 1.6 + 2.6 * math.sin(t)))
    pts.append((BAND, 0.0))
    return pts


def moulding(root, mat, half):
    """The profile swept round a square whose outer edge is `half` (Blender
    units) from the middle: one ring of four mitred corners per profile point,
    so the corners are mitred for free."""
    verts, faces = [], []
    prof = profile()
    for d, h in prof:
        e = half - d * U
        verts += [(-e, e, h * U), (e, e, h * U), (e, -e, h * U), (-e, -e, h * U)]
    for i in range(len(prof) - 1):
        for k in range(4):
            j = (k + 1) % 4
            faces.append((i * 4 + k, i * 4 + j, (i + 1) * 4 + j, (i + 1) * 4 + k))
    obj = lib.mesh_object("Moulding", verts, faces, mat=mat, parent=root, smooth=True)
    rp.fix_normals(obj)
    obj.data.set_sharp_from_angle(angle=math.radians(60))  # crisp mitres, round beads
    return obj


# --------------------------------------------------------------------------
# Ornament pieces, in an ornament's own pixel coordinates: u along the edge,
# v across it (positive towards the window), z up. `m` maps (u, v) before
# placing, so the same code builds the left edge as a mirror of the top.
# --------------------------------------------------------------------------

def same(u, v):
    return (u, v)


def swap(u, v):
    return (v, u)


def at(u, v, z, m=same):
    a, b = m(u, v)
    return (a * U, -b * U, z * U)


def leaf(root, gold, name, base, angle, length, width, z, m=same):
    """A pointed leaf from `base` (u, v) towards `angle`, with a raised rib."""
    ca, sa = math.cos(angle), math.sin(angle)
    half = [(k / 16 * length, width * math.sin(math.pi * k / 16) ** 0.8 * (1 - 0.35 * k / 16)) for k in range(17)]
    outline = half + [(x, -y) for x, y in reversed(half[1:-1])]
    pts = [m(base[0] + x * ca - y * sa, base[1] + x * sa + y * ca) for x, y in outline]
    obj = rp.plate(name, [(x * U, -y * U) for x, y in pts], 2.8 * U, gold, root, bevel_w=1.0 * U)
    obj.location.z = z * U
    rib = [(base[0] + t * length * ca, base[1] + t * length * sa) for t in (0.04, 0.5, 0.96)]
    rp.tube(name + "Rib", [at(x, y, z + 1.7 + (0.9 if i == 1 else 0.0), m) for i, (x, y) in enumerate(rib)],
            [1.3 * U, 1.0 * U, 0.4 * U], gold, root, sides=8)


def scrolls(root, gold, name, u0, length, m=same, sign=1):
    """Two stems waving out along the moulding from u0 (in the direction
    `sign`), one either side of its centre line, each ending in a curl that
    turns away from the centre line, with leaves off them."""
    for side in (-1, 1):
        pts, radii = [], []
        wave = 6.5
        for k in range(29):
            t = k / 28
            u = u0 + sign * length * t
            v = side * (2.0 + wave * math.sin(math.pi * t * 0.9))
            pts.append(at(u, v, 8.4 - 1.2 * t, m))
            radii.append((3.4 - 1.4 * t) * U)
        end_v = side * (2.0 + wave * math.sin(math.pi * 0.9))
        cu, cv = u0 + sign * length, end_v + side * 6.5
        for k in range(1, 19):  # a tightening spiral round a centre outside the stem
            th = -math.pi / 2 + k / 18 * math.radians(320)
            rad = 6.5 * (1 - 0.5 * k / 18)
            pts.append(at(cu + sign * rad * math.cos(th), cv + side * rad * math.sin(th), 7.2 - 0.4 * k / 18, m))
            radii.append((2.0 - 0.9 * k / 18) * U)
        rp.tube(f"{name}{side}", pts, radii, gold, root, sides=10)
        rp.ball(f"{name}End{side}", pts[-1], 1.5 * U, gold, root)
        rp.ball(f"{name}Root{side}", at(u0 + sign * 2.0, side * 2.5, 8.4, m), 2.9 * U, gold, root)
        for k, (f, size) in enumerate(((0.18, 15.0), (0.45, 13.0), (0.7, 10.0))):
            u = u0 + sign * length * f
            v = side * (2.0 + wave * math.sin(math.pi * f * 0.9))
            ang = (0.0 if sign > 0 else math.pi) + sign * side * math.radians(38)
            leaf(root, gold, f"{name}Leaf{side}{k}", (u, v), ang, size, 4.2, 6.4, m)


def rosette(root, gold, stone, name, radius=20.0, oval=1.0):
    """A domed boss with a beaded rim and a set amber stone, at the origin."""
    s = radius / 20.0
    boss = [(0.001, 9.0), (6.0, 9.4), (10.0, 9.0), (14.0, 8.0), (17.0, 6.6), (19.0, 4.8), (19.5, 3.0), (19.0, 2.4)]
    b = rp.lathe(name + "Boss", [(r * s * U, z * U) for r, z in boss], gold, root)
    b.scale = (oval, 1, 1)
    for k in range(18):
        a = math.tau * k / 18
        rp.ball(f"{name}Bead{k}", (17.2 * s * oval * math.cos(a) * U, 17.2 * s * math.sin(a) * U, 7.8 * U),
                1.9 * U, gold, root)
    bezel = ri.torus(name + "Bezel", (0, 0, 10.4 * U), 9.8 * U, 1.7 * U, gold, root)
    bezel.scale = (oval, 1, 1)
    rp.ball(name + "Stone", (0, 0, 10.8 * U), 8.4 * U, stone, root, scale=(oval, 1, 0.62))
    for k in range(4):  # prongs holding the stone
        a = math.tau * (k + 0.5) / 4
        rp.ball(f"{name}Prong{k}", (9.6 * oval * math.cos(a) * U, 9.6 * math.sin(a) * U, 12.2 * U), 1.8 * U,
                gold, root)


def lobed_plate(root, gold, name, radius, z):
    """A four-lobed (quatrefoil) plate under a rosette, its lobes along the
    two edges and pointing out of the frame (none into the window)."""
    outline = []
    for k in range(96):
        a = math.tau * k / 96
        r = radius * (0.78 + 0.22 * abs(math.cos(2 * a)) ** 0.6)
        outline.append((r * math.cos(a) * U, r * math.sin(a) * U))
    obj = rp.plate(name, outline, 3.0 * U, gold, root, bevel_w=1.4 * U)
    obj.location.z = z * U
    ri.torus(name + "Rim", (0, 0, z * U + 1.6 * U), radius * 0.74 * U, 1.0 * U, gold, root)


def corner(root, gold, stone):
    """The ornament for the top-left corner, round the moulding's centre
    line at the corner (the origin)."""
    lobed_plate(root, gold, "Plate", 32.0, 6.0)
    rosette(root, gold, stone, "Rose", 21.0)
    diag = math.radians(225)  # out of the corner: up and to the left
    leaf(root, gold, "Finial", (-14.0, -14.0), diag, 36.0, 11.0, 5.0)
    leaf(root, gold, "FinialA", (-17.0, -6.0), diag + math.radians(36), 26.0, 6.5, 4.0)
    leaf(root, gold, "FinialB", (-6.0, -17.0), diag - math.radians(36), 26.0, 6.5, 4.0)
    scrolls(root, gold, "Top", 24.0, 62.0, same)
    scrolls(root, gold, "Left", 24.0, 62.0, swap)


def crest(root, gold, stone):
    """The mid-side ornament, centred on the moulding's centre line: an oval
    medallion, scrolls either way, a crowning leaf outside and a bead below."""
    rosette(root, gold, stone, "Medal", 18.0, oval=1.35)
    leaf(root, gold, "Crown", (0.0, -15.0), math.radians(-90), 26.0, 8.0, 5.0)
    leaf(root, gold, "CrownA", (-6.0, -14.0), math.radians(-90 - 38), 17.0, 5.0, 4.2)
    leaf(root, gold, "CrownB", (6.0, -14.0), math.radians(-90 + 38), 17.0, 5.0, 4.2)
    rp.ball("Drop", at(0.0, 17.5, 7.0), 3.2 * U, gold, root)
    scrolls(root, gold, "Right", 22.0, 52.0, same, 1)
    scrolls(root, gold, "Leftward", -22.0, 52.0, same, -1)


# --------------------------------------------------------------------------
# Building and compositing
# --------------------------------------------------------------------------

def build_frame():
    root = scene(SIZE, SIZE)
    gold, stone = materials()
    moulding(root, gold, (SIZE / 2 - OUT) * U)
    c = (OUT + BAND / 2 - SIZE / 2) * U
    for k in range(4):  # the top-left ornament, turned a quarter at a time
        g = rp.group(f"Corner{k}", root, rot=(0, 0, -math.pi / 2 * k))
        corner(g, gold, stone)
        g.location = Vector((c, -c, 0))
        g.location.rotate(g.rotation_euler)


def build_crest(side):
    w, hgt = CREST
    turn = CREST_SIDES[side]
    root = scene(*((w, hgt) if side in ("top", "bottom") else (hgt, w)))
    gold, stone = materials()
    g = rp.group("Crest", root, rot=(0, 0, turn))
    crest(g, gold, stone)
    offset = Vector((0, (hgt / 2 - CREST_LINE) * U, 0))  # the centre line CREST_LINE px from the outer edge
    offset.rotate(g.rotation_euler)
    g.location = offset


def shadowed(img: Image.Image, offset=(2, 4), blur=4, strength=0.7) -> Image.Image:
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(img.split()[3].point(lambda a: int(a * strength)))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)), offset)
    out.alpha_composite(img)
    return out


def composite_frame(render: Image.Image) -> Image.Image:
    """The rendered gold over the panel's background, with an inner shadow,
    a fine rule inside the moulding and a soft drop shadow outside."""
    frame = render.resize((SIZE, SIZE), Image.LANCZOS)
    inner = OUT + BAND // 2
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(bg).rectangle((inner, inner, SIZE - 1 - inner, SIZE - 1 - inner), fill=BG + (255,))
    edge = OUT + BAND
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    dist = np.minimum.reduce([xx - edge, yy - edge, SIZE - 1 - edge - xx, SIZE - 1 - edge - yy]).astype(np.float32)
    shade = np.zeros((SIZE, SIZE, 4), np.uint8)
    fall = np.where(dist >= 0, np.clip(1.0 - dist / 16.0, 0.0, 1.0) ** 2, 0.0)  # only inside the moulding
    shade[..., 3] = (fall * 0.6 * 255).astype(np.uint8)
    bg.alpha_composite(Image.fromarray(shade, "RGBA"))
    r = edge + 8
    ImageDraw.Draw(bg).rectangle((r, r, SIZE - 1 - r, SIZE - 1 - r), outline=RULE + (190,), width=1)
    bg.alpha_composite(shadowed(frame))
    return bg


def run(names=None):
    names = names or ["frame_gold", "frame_gold_crest"]
    if "frame_gold" in names:
        build_frame()
        path = lib.ASSETS / "ui" / "frame_gold.png"
        composite_frame(lib.render(path)).save(path)
        print("wrote", path)
    if "frame_gold_crest" in names:
        for side in CREST_SIDES:
            build_crest(side)
            path = lib.ASSETS / "ui" / f"frame_gold_crest_{side}.png"
            size = CREST if side in ("top", "bottom") else (CREST[1], CREST[0])
            shadowed(lib.render(path).resize(size, Image.LANCZOS), blur=3).save(path)
            print("wrote", path)
