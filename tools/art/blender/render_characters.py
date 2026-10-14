"""Pre-rendered character sprites (and portraits) from simple 3D figures.

Figures are built from smooth lofted shapes, posed standing and turned a little
towards screen-right (the game mirrors the sprite when walking left). They are
rendered with the prop camera, at slightly heroic scale so they read clearly
next to 5 ft hexes. The feet pixel is written to every character sheet that
uses the sprite (art.sprite_origin).
"""
import json
import math

import bpy
from mathutils import Euler, Vector

import lib

SAMPLES = 128
HERO_SCALE = 1.2
FACING = math.radians(22)  # turn towards screen-right


# --------------------------------------------------------------------------
# Shape helpers
# --------------------------------------------------------------------------

def loft(name, sections, mat, parent, sides=16, cap=True, smooth=True):
    """Tube through elliptical sections [(z, rx, ry, cx, cy), ...] (bottom to top)."""
    verts, faces = [], []
    for (z, rx, ry, cx, cy) in sections:
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append((cx + math.cos(a) * rx, cy + math.sin(a) * ry, z))
    for s in range(len(sections) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            a, b = s * sides + i, s * sides + j
            faces.append((a, b, b + sides, a + sides))
    if cap:
        faces.append(tuple(range(sides))[::-1])
        top = (len(sections) - 1) * sides
        faces.append(tuple(range(top, top + sides)))
    obj = lib.mesh_object(name, verts, faces, mat=mat, parent=parent, smooth=smooth)
    return obj


def limb(name, points, radii, mat, parent, sides=12):
    """Smooth tube along a polyline with per-point radii, plus round ends."""
    pts = [Vector(p) for p in points]
    verts, faces = [], []
    for k, (p, r) in enumerate(zip(pts, radii)):
        if k < len(pts) - 1:
            d = (pts[k + 1] - p).normalized()
        else:
            d = (p - pts[k - 1]).normalized()
        q = d.to_track_quat('Z', 'Y').to_matrix()
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append(p + q @ Vector((math.cos(a) * r, math.sin(a) * r, 0)))
    for s in range(len(pts) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            a, b = s * sides + i, s * sides + j
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(range(sides))[::-1])
    top = (len(pts) - 1) * sides
    faces.append(tuple(range(top, top + sides)))
    obj = lib.mesh_object(name, verts, faces, mat=mat, parent=parent, smooth=True)
    for p, r in ((pts[0], radii[0]), (pts[-1], radii[-1])):
        sphere(name + "_joint", p, (r, r, r), mat, parent, segments=12)
    return obj


def sphere(name, center, radii, mat, parent, segments=16):
    obj = lib.primitive("uv_sphere", name, mat=mat, parent=parent, segments=segments, ring_count=segments // 2,
                        radius=1.0, location=tuple(center))
    obj.scale = radii
    obj.data.shade_smooth()
    return obj


def mat(name, color, rough=0.7, metallic=0.0, bump=0.0, bump_scale=60, noise_var=0.0, emission=None, strength=0.0):
    return lib.material(name, lib.lin(color), rough=rough, metallic=metallic, bump=bump, bump_scale=bump_scale,
                        noise_var=noise_var, noise_scale=12, emission=lib.lin(emission) if emission else None,
                        emission_strength=strength)


# --------------------------------------------------------------------------
# Body
# --------------------------------------------------------------------------

def body(root, h=1.8, build=1.0, skin="#c99a74", shirt="#6b5a40", trousers="#4a3a2a", boots="#2e241c",
         arms_out=0.2, hair=None, hair_style="short", head_cover=False, skip_legs=False, eye="#2a2018"):
    """A standing figure of height h. Returns key points for gear placement."""
    s = h / 1.8
    w = build
    m_skin = mat("Skin", skin, rough=0.6)
    m_shirt = mat("Shirt", shirt, rough=0.85, noise_var=0.15)
    m_trousers = mat("Trousers", trousers, rough=0.85, noise_var=0.15)
    m_boots = mat("Boots", boots, rough=0.6)
    hip_z, knee_z, ankle_z = 0.92 * s, 0.5 * s, 0.1 * s
    if not skip_legs:
        for side in (-1, 1):
            x = side * 0.1 * s * w
            limb(f"Leg{side}", [(x, 0, hip_z), (x * 1.05, -0.02 * s, knee_z), (x * 1.1, 0, ankle_z + 0.05 * s)],
                 [0.075 * s * w, 0.058 * s * w, 0.045 * s * w], m_trousers, root)
            limb(f"Boot{side}", [(x * 1.1, 0.01 * s, 0.32 * s), (x * 1.1, 0, ankle_z)], [0.055 * s * w, 0.05 * s * w],
                 m_boots, root)
            sphere(f"Foot{side}", (x * 1.1, -0.06 * s, 0.045 * s), (0.055 * s * w, 0.12 * s, 0.045 * s), m_boots, root)
    loft("Torso", [(0.88 * s, 0.17 * s * w, 0.11 * s * w, 0, 0), (1.0 * s, 0.16 * s * w, 0.1 * s * w, 0, 0),
                   (1.15 * s, 0.17 * s * w, 0.11 * s * w, 0, -0.005), (1.32 * s, 0.2 * s * w, 0.12 * s * w, 0, -0.01),
                   (1.42 * s, 0.21 * s * w, 0.11 * s * w, 0, 0), (1.47 * s, 0.12 * s * w, 0.08 * s, 0, 0)],
         m_shirt, root)
    sh_z = 1.4 * s
    hands = []
    for side in (-1, 1):
        sx = side * 0.2 * s * w
        elbow = (side * (0.25 * s * w + arms_out * 0.15 * s), -0.02 * s, 1.12 * s)
        hand = (side * (0.27 * s * w + arms_out * 0.3 * s), -0.06 * s, 0.86 * s)
        limb(f"Arm{side}", [(sx, 0, sh_z), elbow, hand], [0.055 * s * w, 0.045 * s * w, 0.04 * s * w], m_shirt, root)
        sphere(f"Hand{side}", hand, (0.045 * s, 0.04 * s, 0.055 * s), m_skin, root)
        hands.append(Vector(hand))
    limb("Neck", [(0, 0, 1.44 * s), (0, -0.01 * s, 1.55 * s)], [0.05 * s, 0.048 * s], m_skin, root)
    head_c = Vector((0, -0.015 * s, 1.66 * s))
    sphere("Head", head_c, (0.095 * s, 0.105 * s, 0.12 * s), m_skin, root, segments=24)
    sphere("Nose", head_c + Vector((0, -0.1 * s, -0.01 * s)), (0.018 * s, 0.03 * s, 0.03 * s), m_skin, root, 10)
    m_eye = mat("Eye", eye, rough=0.3)
    for side in (-1, 1):
        sphere(f"Eye{side}", head_c + Vector((side * 0.038 * s, -0.088 * s, 0.015 * s)), (0.014 * s,) * 3, m_eye, root, 8)
        sphere(f"Ear{side}", head_c + Vector((side * 0.095 * s, 0, 0)), (0.018 * s, 0.03 * s, 0.035 * s), m_skin, root, 8)
    if hair and not head_cover:
        m_hair = mat("Hair", hair, rough=0.6, bump=0.4, bump_scale=120)
        if hair_style == "short":
            sphere("Hair", head_c + Vector((0, 0.012 * s, 0.03 * s)), (0.102 * s, 0.11 * s, 0.11 * s), m_hair, root, 20)
        elif hair_style == "long":
            sphere("Hair", head_c + Vector((0, 0.015 * s, 0.025 * s)), (0.104 * s, 0.112 * s, 0.115 * s), m_hair, root, 20)
            loft("HairBack", [(1.2 * s, 0.11 * s, 0.05 * s, 0, 0.07 * s), (1.45 * s, 0.12 * s, 0.07 * s, 0, 0.06 * s),
                              (1.68 * s, 0.1 * s, 0.08 * s, 0, 0.02 * s)], m_hair, root)
    return {"s": s, "hands": hands, "head": head_c, "shoulder_z": sh_z, "hip_z": hip_z, "skin": m_skin}


# --------------------------------------------------------------------------
# Characters
# --------------------------------------------------------------------------

def setup():
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=(0.62, 0.70, 0.82), sky_strength=1.0)
    lib.add_sun(strength=4.0, angle_deg=3.0)
    # Rim light from behind to separate figures from the ground.
    lib.add_sun(strength=2.2, angle_deg=8.0, color=(0.9, 0.95, 1.0), direction=Vector((-0.4, -0.7, -0.35)))
    root = bpy.data.objects.new("Figure", None)
    bpy.context.scene.collection.objects.link(root)
    root.scale = (HERO_SCALE,) * 3
    root.rotation_euler = Euler((0, 0, FACING))
    return root


def fighter(root):
    b = body(root, h=1.82, build=1.08, skin="#c99a74", shirt="#5a6270", trousers="#3f3a34", boots="#3a2a1e",
             hair="#3b2617", hair_style="short")
    s = b["s"]
    mail = mat("Mail", "#7d838c", rough=0.45, metallic=0.85, bump=0.6, bump_scale=300)
    loft("Mail", [(0.62 * s, 0.2 * s, 0.14 * s, 0, 0), (0.9 * s, 0.19 * s, 0.13 * s, 0, 0),
                  (1.15 * s, 0.19 * s, 0.125 * s, 0, 0), (1.34 * s, 0.22 * s, 0.13 * s, 0, 0),
                  (1.44 * s, 0.22 * s, 0.12 * s, 0, 0)], mail, root)
    tabard = mat("Tabard", "#8e2424", rough=0.85, noise_var=0.2)
    lib.box("TabardFront", (0.22 * s, 0.02, 0.75 * s), (0, -0.135 * s, 0.98 * s), mat=tabard, parent=root, bevel=0.01)
    belt = mat("Belt", "#3a2618", rough=0.6)
    loft("Belt", [(0.9 * s, 0.205 * s, 0.14 * s, 0, 0), (0.95 * s, 0.205 * s, 0.14 * s, 0, 0)], belt, root)
    steel = mat("Steel", "#b8bcc4", rough=0.25, metallic=1.0)
    for side in (-1, 1):
        sphere(f"Pauldron{side}", (side * 0.23 * s, 0, 1.42 * s), (0.1 * s, 0.1 * s, 0.07 * s), steel, root)
    # Shield on the left arm, facing forward.
    lh = b["hands"][0]
    wood = mat("ShieldWood", "#6b4a2b", rough=0.7, noise_var=0.2)
    sh = lib.primitive("cylinder", "Shield", mat=wood, parent=root, vertices=32, radius=0.3 * s, depth=0.04,
                       location=(lh.x - 0.06, lh.y - 0.12, lh.z + 0.2 * s))
    sh.rotation_euler = (math.radians(90), 0, math.radians(-15))
    rim = lib.primitive("torus", "ShieldRim", mat=steel, parent=root, major_radius=0.3 * s, minor_radius=0.02,
                        location=sh.location)
    rim.rotation_euler = sh.rotation_euler
    boss = sphere("Boss", (sh.location.x - 0.01, sh.location.y - 0.04, sh.location.z), (0.06, 0.04, 0.06), steel, root)
    # Longsword in the right hand, point down and forward.
    rh = b["hands"][1]
    lib.box("Blade", (0.05, 0.012, 0.85 * s), (rh.x + 0.03, rh.y - 0.12, rh.z - 0.32 * s), mat=steel, parent=root,
            rotation=(math.radians(-18), 0, 0), bevel=0.004)
    gold = mat("Brass", "#a8842e", rough=0.35, metallic=0.9)
    lib.box("Guard", (0.22, 0.03, 0.03), (rh.x + 0.02, rh.y - 0.05, rh.z + 0.06), mat=gold, parent=root)
    sphere("Pommel", (rh.x + 0.01, rh.y - 0.01, rh.z + 0.17), (0.025,) * 3, gold, root)
    _ = boss


def wizard(root):
    b = body(root, h=1.78, build=0.92, skin="#e8cdb2", shirt="#4f3279", trousers="#4f3279", boots="#2a1f2f",
             hair="#dfe3ea", hair_style="long", skip_legs=True, eye="#3a6e8c")
    s = b["s"]
    robe = mat("Robe", "#4a3068", rough=0.9, noise_var=0.25, bump=0.2, bump_scale=30)
    trim = mat("Trim", "#b8922e", rough=0.4, metallic=0.7)
    loft("Robe", [(0.0, 0.3 * s, 0.26 * s, 0, 0.0), (0.4 * s, 0.25 * s, 0.2 * s, 0, 0),
                  (0.9 * s, 0.18 * s, 0.13 * s, 0, 0), (1.2 * s, 0.18 * s, 0.12 * s, 0, 0),
                  (1.4 * s, 0.21 * s, 0.12 * s, 0, 0), (1.47 * s, 0.12 * s, 0.08 * s, 0, 0)], robe, root)
    loft("Hem", [(0.0, 0.305 * s, 0.265 * s, 0, 0), (0.06 * s, 0.295 * s, 0.255 * s, 0, 0)], trim, root)
    loft("Sash", [(0.9 * s, 0.185 * s, 0.135 * s, 0, 0), (0.95 * s, 0.185 * s, 0.135 * s, 0, 0)], trim, root)
    # Pointed hat.
    hc = b["head"]
    hat = mat("Hat", "#45296c", rough=0.9, noise_var=0.2)
    brim = lib.primitive("cylinder", "Brim", mat=hat, parent=root, vertices=32, radius=0.15 * s, depth=0.015,
                         location=(hc.x, hc.y + 0.03 * s, hc.z + 0.1 * s))
    brim.rotation_euler = (math.radians(14), 0, 0)
    cone = lib.primitive("cone", "HatCone", mat=hat, parent=root, vertices=24, radius1=0.1 * s, radius2=0.01,
                         depth=0.34 * s, location=(hc.x, hc.y + 0.06 * s, hc.z + 0.27 * s))
    cone.rotation_euler = (math.radians(18), 0, 0)
    loft("HatBand", [(hc.z + 0.1 * s, 0.103 * s, 0.103 * s, hc.x, hc.y + 0.03 * s),
                     (hc.z + 0.13 * s, 0.099 * s, 0.099 * s, hc.x, hc.y + 0.035 * s)], trim, root)
    # Staff with glowing crystal.
    rh = b["hands"][1]
    staff = mat("Staff", "#5a3d22", rough=0.7, noise_var=0.3)
    lib.cylinder_between("Staff", (rh.x + 0.02, rh.y - 0.02, 0.02), (rh.x + 0.04, rh.y - 0.04, 1.95 * s), 0.022,
                         mat=staff, parent=root, sides=10)
    crystal = mat("Crystal", "#9fe8ff", rough=0.1, emission="#7fdcff", strength=6.0)
    gem = lib.primitive("ico_sphere", "Crystal", mat=crystal, parent=root, subdivisions=1, radius=0.06 * s,
                        location=(rh.x + 0.04, rh.y - 0.04, 2.02 * s))
    gem.scale = (0.8, 0.8, 1.4)
    _ = brim


def cleric(root):
    b = body(root, h=1.38, build=1.35, skin="#8d5a3b", shirt="#d9d2bf", trousers="#5a4a38", boots="#3a2a1e",
             hair=None, eye="#3b2a1a")
    s = b["s"]
    mail = mat("Mail", "#7d838c", rough=0.45, metallic=0.85, bump=0.6, bump_scale=300)
    loft("Mail", [(0.55 * s, 0.25 * s, 0.18 * s, 0, 0), (0.9 * s, 0.25 * s, 0.17 * s, 0, 0),
                  (1.3 * s, 0.28 * s, 0.17 * s, 0, 0), (1.44 * s, 0.27 * s, 0.15 * s, 0, 0)], mail, root)
    cloth = mat("Vestment", "#e2dbc8", rough=0.9, noise_var=0.15)
    lib.box("Tabard", (0.3 * s, 0.02, 0.85 * s), (0, -0.18 * s, 0.95 * s), mat=cloth, parent=root, bevel=0.01)
    gold = mat("Gold", "#d8b04a", rough=0.3, metallic=1.0)
    sun = lib.primitive("cylinder", "Sun", mat=gold, parent=root, vertices=24, radius=0.07 * s, depth=0.015,
                        location=(0, -0.195 * s, 1.18 * s))
    sun.rotation_euler = (math.radians(90), 0, 0)
    lib.box("TrimL", (0.03, 0.025, 0.85 * s), (-0.15 * s, -0.19 * s, 0.95 * s), mat=gold, parent=root)
    lib.box("TrimR", (0.03, 0.025, 0.85 * s), (0.15 * s, -0.19 * s, 0.95 * s), mat=gold, parent=root)
    # Great beard and a circlet.
    hc = b["head"]
    beard = mat("Beard", "#6a3f22", rough=0.7, bump=0.6, bump_scale=150)
    loft("Beard", [(hc.z - 0.42 * s, 0.03 * s, 0.03 * s, 0, -0.14 * s), (hc.z - 0.25 * s, 0.11 * s, 0.07 * s, 0, -0.12 * s),
                   (hc.z - 0.08 * s, 0.1 * s, 0.07 * s, 0, -0.07 * s), (hc.z + 0.0, 0.085 * s, 0.05 * s, 0, -0.05 * s)],
         beard, root)
    loft("Circlet", [(hc.z + 0.04 * s, 0.1 * s, 0.112 * s, hc.x, hc.y), (hc.z + 0.065 * s, 0.098 * s, 0.11 * s, hc.x, hc.y)],
         gold, root)
    # Mace.
    rh = b["hands"][1]
    wood = mat("Haft", "#4a3422", rough=0.7)
    lib.cylinder_between("Haft", (rh.x, rh.y - 0.02, rh.z - 0.1), (rh.x + 0.03, rh.y - 0.14, rh.z + 0.42 * s), 0.02,
                         mat=wood, parent=root, sides=8)
    steel = mat("Steel", "#9aa0a8", rough=0.3, metallic=1.0)
    head = Vector((rh.x + 0.035, rh.y - 0.16, rh.z + 0.47 * s))
    sphere("MaceHead", head, (0.065, 0.065, 0.075), steel, root)
    for k in range(6):
        a = k * math.pi / 3
        lib.box(f"Flange{k}", (0.02, 0.06, 0.12), (head.x + math.cos(a) * 0.06, head.y + math.sin(a) * 0.06, head.z),
                mat=steel, parent=root, rotation=(0, 0, a))


def rogue(root):
    b = body(root, h=1.08, build=1.0, skin="#e0b28a", shirt="#4f3e2c", trousers="#3a2f24", boots="#241c15",
             hair="#8c3f1f", hair_style="short", eye="#4c7a3a")
    s = b["s"]
    cloak = mat("Cloak", "#2c4636", rough=0.95, noise_var=0.25, bump=0.3, bump_scale=25)
    loft("Cloak", [(0.38 * s, 0.27 * s, 0.2 * s, 0, 0.05 * s), (0.8 * s, 0.24 * s, 0.17 * s, 0, 0.04 * s),
                   (1.2 * s, 0.22 * s, 0.14 * s, 0, 0.02 * s), (1.42 * s, 0.24 * s, 0.13 * s, 0, 0.01 * s),
                   (1.5 * s, 0.13 * s, 0.1 * s, 0, 0.01 * s)], cloak, root, cap=False)
    hc = b["head"]
    hood = sphere("Hood", hc + Vector((0, 0.03 * s, 0.02 * s)), (0.13 * s, 0.13 * s, 0.14 * s), cloak, root, 20)
    scarf = mat("Scarf", "#2a2722", rough=0.9)
    sphere("Mask", hc + Vector((0, -0.04 * s, -0.06 * s)), (0.09 * s, 0.08 * s, 0.055 * s), scarf, root, 16)
    leather = mat("Leather", "#5a4430", rough=0.6, noise_var=0.2)
    lib.box("Bandolier", (0.06, 0.02, 0.5 * s), (0, -0.14 * s, 1.15 * s), mat=leather, parent=root,
            rotation=(0, math.radians(35), 0))
    steel = mat("Steel", "#c0c4cc", rough=0.2, metallic=1.0)
    for side, hand in zip((-1, 1), b["hands"]):
        lib.box(f"Dagger{side}", (0.025, 0.008, 0.26), (hand.x + side * 0.02, hand.y - 0.05, hand.z - 0.12),
                mat=steel, parent=root, rotation=(math.radians(-25), side * math.radians(10), 0), bevel=0.003)
    _ = hood


CHARACTERS = {
    "fighter": fighter,
    "wizard": wizard,
    "cleric": cleric,
    "rogue": rogue,
}


def render_sprite(name):
    root = setup()
    CHARACTERS[name](root)
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    cam, res = lib.frame_oblique(objs, margin_px=4)
    path = lib.ASSETS / "characters" / f"{name}.png"
    lib.render(path, res=res)
    feet = lib.to_pixel(cam, Vector((0, 0, 0)), res)
    print("wrote", path, res, "feet", feet)
    return [round(feet[0]), round(feet[1])]


def update_sheets(origins):
    """Stores each sprite's feet pixel as art.sprite_origin in the sheets using it."""
    for path in sorted((lib.ROOT / "data" / "characters").glob("*.json")):
        data = json.loads(path.read_text())
        sprite = data.get("art", {}).get("sprite", "")
        for name, origin in origins.items():
            if sprite.endswith(f"/characters/{name}.png"):
                data["art"]["sprite_origin"] = origin
                path.write_text(json.dumps(data, indent="\t") + "\n")
                print("updated", path.name, origin)


def run(names=None):
    origins = {}
    for name in names or CHARACTERS:
        origins[name] = render_sprite(name)
    update_sheets(origins)
