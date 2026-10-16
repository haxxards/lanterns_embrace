"""Pre-rendered, animated character sprites from simple 3D figures.

Figures are built from smooth lofted shapes with posable limbs. Each class is
rendered as a sprite sheet: 5 facings (S, SE, E, NE, N; the game mirrors them
for SW, W, NW) x 9 frames (idle + an 8-frame walk cycle), all with the feet at
the same pixel in every cell. A JSON file next to the sheet describes it, and
the character sheets that use the class point at it (art.animation). A single
idle frame is also written as the class's static sprite.
"""
import json
import math

import bpy
import numpy as np
from mathutils import Euler, Vector

import lib

SAMPLES = 64
HERO_SCALE = 1.25
DIRECTIONS = [("s", 0), ("se", 45), ("e", 90), ("ne", 135), ("n", 180)]
WALK_FRAMES = 8
# Current pose, read by body(): phase of the walk cycle and how much walking.
POSE = {"phase": 0.0, "walk": 0.0}


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

def _down(theta):
    """Unit vector pointing down, swung forward (towards -y) by theta."""
    return Vector((0.0, -math.sin(theta), -math.cos(theta)))


def leg_pose(side, s):
    """Hip swing and knee bend for one leg at the current POSE."""
    phase = POSE["phase"] + (0.0 if side < 0 else math.pi)
    walk = POSE["walk"]
    swing = 0.42 * math.sin(phase) * walk
    bend = walk * (0.12 + 0.55 * max(0.0, math.cos(phase)))
    thigh, shin = 0.43 * s, 0.42 * s
    knee = _down(swing) * thigh
    ankle = knee + _down(swing - bend) * shin
    return swing, bend, knee, ankle


def body(root, h=1.8, build=1.0, skin="#c99a74", shirt="#6b5a40", trousers="#4a3a2a", boots="#2e241c",
         arms_out=0.2, hair=None, hair_style="short", head_cover=False, skip_legs=False, eye="#2a2018"):
    """A figure of height h in the current POSE. Returns key points for gear."""
    s = h / 1.8
    w = build
    m_skin = mat("Skin", skin, rough=0.6)
    m_shirt = mat("Shirt", shirt, rough=0.85, noise_var=0.15)
    m_trousers = mat("Trousers", trousers, rough=0.85, noise_var=0.15)
    m_boots = mat("Boots", boots, rough=0.55, bump=0.2, bump_scale=80)
    hip_z = 0.92 * s
    # How far the whole figure must drop so the lower foot stays on the ground
    # through the stride; applied to the figure root after the gear is built.
    lows = [leg_pose(side, s)[3].z for side in (-1, 1)]
    POSE["lift"] = -min(lows) - hip_z + 0.07 * s
    if not skip_legs:
        for side in (-1, 1):
            x = side * 0.1 * s * w
            swing, bend, knee, ankle = leg_pose(side, s)
            hip = Vector((x, 0, hip_z))
            k = hip + knee
            a = hip + ankle
            limb(f"Thigh{side}", [hip, k], [0.08 * s * w, 0.06 * s * w], m_trousers, root)
            calf = k + (a - k) * 0.35 + Vector((0, 0.012 * s, 0))
            limb(f"Shin{side}", [k, calf, a], [0.058 * s * w, 0.06 * s * w, 0.045 * s * w], m_trousers, root)
            boot_top = a + (k - a).normalized() * 0.2 * s
            limb(f"Boot{side}", [boot_top, a], [0.058 * s * w, 0.05 * s * w], m_boots, root)
            toe_dir = _down(swing - bend * 0.4 + math.pi / 2)
            toe = a + toe_dir * 0.13 * s + Vector((0, 0, -0.03 * s))
            limb(f"Foot{side}", [a + Vector((0, 0.03 * s, -0.025 * s)), toe], [0.05 * s * w, 0.04 * s * w], m_boots, root)
    tilt = 0.012 * s * POSE["walk"]  # walkers lean slightly forward
    loft("Pelvis", [(hip_z - 0.06 * s, 0.15 * s * w, 0.1 * s * w, 0, 0), (hip_z + 0.04 * s, 0.17 * s * w, 0.11 * s * w, 0, 0)],
         m_trousers, root)
    loft("Torso", [(hip_z - 0.04 * s, 0.17 * s * w, 0.11 * s * w, 0, 0),
                   (hip_z + 0.08 * s, 0.155 * s * w, 0.1 * s * w, 0, -tilt * 0.3),
                   (hip_z + 0.23 * s, 0.17 * s * w, 0.115 * s * w, 0, -0.012 * s - tilt * 0.6),
                   (hip_z + 0.38 * s, 0.2 * s * w, 0.125 * s * w, 0, -0.018 * s - tilt),
                   (hip_z + 0.48 * s, 0.21 * s * w, 0.11 * s * w, 0, -0.008 * s - tilt),
                   (hip_z + 0.54 * s, 0.12 * s * w, 0.08 * s, 0, -tilt)], m_shirt, root)
    sh_z = hip_z + 0.48 * s
    hands = []
    for side in (-1, 1):
        phase = POSE["phase"] + (0.0 if side < 0 else math.pi)
        swing = -0.38 * math.sin(phase) * POSE["walk"]
        sx = side * 0.21 * s * w
        shoulder = Vector((sx, -tilt, sh_z))
        sphere(f"Deltoid{side}", shoulder, (0.07 * s * w, 0.07 * s * w, 0.06 * s * w), m_shirt, root)
        out = Vector((side * arms_out * 0.12 * s, 0, 0))
        elbow = shoulder + _down(swing) * 0.29 * s + out + Vector((side * 0.03 * s * w, 0, 0))
        hand = elbow + _down(swing + 0.2 + 0.25 * POSE["walk"]) * 0.27 * s + out * 0.8
        limb(f"Arm{side}", [shoulder, elbow, hand], [0.055 * s * w, 0.047 * s * w, 0.04 * s * w], m_shirt, root)
        sphere(f"Hand{side}", hand, (0.042 * s, 0.038 * s, 0.055 * s), m_skin, root)
        hands.append(hand)
    neck_base = Vector((0, -tilt, sh_z + 0.04 * s))
    limb("Neck", [neck_base, neck_base + Vector((0, -0.01 * s, 0.11 * s))], [0.05 * s, 0.048 * s], m_skin, root)
    head_c = neck_base + Vector((0, -0.02 * s, 0.22 * s))
    sphere("Head", head_c, (0.095 * s, 0.105 * s, 0.12 * s), m_skin, root, segments=24)
    sphere("Jaw", head_c + Vector((0, -0.02 * s, -0.06 * s)), (0.075 * s, 0.08 * s, 0.07 * s), m_skin, root, 16)
    sphere("Nose", head_c + Vector((0, -0.1 * s, -0.01 * s)), (0.018 * s, 0.03 * s, 0.03 * s), m_skin, root, 10)
    m_eye = mat("Eye", eye, rough=0.3)
    for side in (-1, 1):
        sphere(f"Eye{side}", head_c + Vector((side * 0.038 * s, -0.088 * s, 0.015 * s)), (0.014 * s,) * 3, m_eye, root, 8)
        sphere(f"Ear{side}", head_c + Vector((side * 0.095 * s, 0, 0)), (0.018 * s, 0.03 * s, 0.035 * s), m_skin, root, 8)
    if hair and not head_cover:
        m_hair = mat("Hair", hair, rough=0.6, bump=0.4, bump_scale=120)
        if hair_style == "short":
            sphere("Hair", head_c + Vector((0, 0.018 * s, 0.035 * s)), (0.1 * s, 0.108 * s, 0.105 * s), m_hair, root, 20)
        elif hair_style == "long":
            sphere("Hair", head_c + Vector((0, 0.02 * s, 0.03 * s)), (0.102 * s, 0.11 * s, 0.11 * s), m_hair, root, 20)
            z0 = head_c.z
            loft("HairBack", [(z0 - 0.46 * s, 0.11 * s, 0.05 * s, 0, 0.07 * s - tilt), (z0 - 0.21 * s, 0.12 * s, 0.07 * s, 0, 0.06 * s - tilt),
                              (z0 + 0.02 * s, 0.1 * s, 0.08 * s, 0, 0.02 * s - tilt)], m_hair, root)
    return {"s": s, "hands": hands, "head": head_c, "shoulder_z": sh_z, "hip_z": hip_z, "skin": m_skin}


# --------------------------------------------------------------------------
# Characters
# --------------------------------------------------------------------------

def setup(yaw_deg=22.0):
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=(0.62, 0.70, 0.82), sky_strength=1.0)
    lib.add_sun(strength=4.0, angle_deg=3.0)
    # Rim light from behind to separate figures from the ground.
    lib.add_sun(strength=2.2, angle_deg=8.0, color=(0.9, 0.95, 1.0), direction=Vector((-0.4, -0.7, -0.35)))
    root = bpy.data.objects.new("Figure", None)
    bpy.context.scene.collection.objects.link(root)
    root.scale = (HERO_SCALE,) * 3
    root.rotation_euler = Euler((0, 0, math.radians(yaw_deg)))
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


# --------------------------------------------------------------------------
# Townsfolk (NPCs)
# --------------------------------------------------------------------------

def apron(root, s, color, top=1.25, bottom=0.45, width=0.36, y=-0.16):
    m = mat("Apron", color, rough=0.9, noise_var=0.2)
    lib.box("Apron", (width * s, 0.02, (top - bottom) * s), (0, y * s, (top + bottom) / 2 * s), mat=m, parent=root,
            bevel=0.01)
    loft("ApronTie", [(0.9 * s, 0.21 * s, 0.15 * s, 0, 0), (0.93 * s, 0.21 * s, 0.15 * s, 0, 0)], m, root)


def skirt(root, s, color, waist=0.92, hem=0.0, flare=0.3):
    m = mat("Skirt", color, rough=0.9, noise_var=0.2, bump=0.2, bump_scale=30)
    loft("Skirt", [(hem, flare * s, (flare - 0.04) * s, 0, 0.01 * s), (0.45 * s, 0.24 * s, 0.19 * s, 0, 0),
                   (waist * s, 0.17 * s, 0.12 * s, 0, 0)], m, root)
    return m


def innkeeper(root):
    b = body(root, h=1.74, build=1.28, skin="#d8a882", shirt="#d9cfb6", trousers="#4a3a2a", boots="#3a2a1e",
             hair="#8a8478", hair_style="short", eye="#3a2a1a")
    s = b["s"]
    apron(root, s, "#efe8d6", top=1.2, bottom=0.42, width=0.4, y=-0.165)
    vest = mat("Vest", "#5a3a24", rough=0.8, noise_var=0.2)
    loft("Vest", [(1.05 * s, 0.215 * s, 0.14 * s, 0, 0), (1.3 * s, 0.22 * s, 0.135 * s, 0, 0),
                  (1.42 * s, 0.23 * s, 0.12 * s, 0, 0)], vest, root, cap=False)
    rh = b["hands"][1]
    wood = mat("Tankard", "#8a6a44", rough=0.6)
    lib.primitive("cylinder", "Tankard", mat=wood, parent=root, vertices=14, radius=0.05, depth=0.13,
                  location=(rh.x, rh.y - 0.04, rh.z + 0.04))


def smith(root):
    b = body(root, h=1.84, build=1.32, skin="#b98260", shirt="#b98260", trousers="#3a3530", boots="#2a201a",
             hair="#2a1e16", hair_style="short", eye="#2a2018")
    s = b["s"]
    apron(root, s, "#4a3020", top=1.38, bottom=0.4, width=0.42, y=-0.17)
    hc = b["head"]
    beard = mat("Beard", "#2a1e16", rough=0.7, bump=0.5, bump_scale=150)
    loft("Beard", [(hc.z - 0.2 * s, 0.05 * s, 0.04 * s, 0, -0.1 * s), (hc.z - 0.08 * s, 0.09 * s, 0.06 * s, 0, -0.07 * s),
                   (hc.z, 0.085 * s, 0.05 * s, 0, -0.05 * s)], beard, root)
    rh = b["hands"][1]
    lib.cylinder_between("Haft", (rh.x, rh.y, rh.z - 0.05), (rh.x + 0.02, rh.y - 0.08, rh.z + 0.35 * s), 0.018,
                         mat=mat("Haft", "#5a3d22", rough=0.7), parent=root, sides=8)
    lib.box("HammerHead", (0.09, 0.14, 0.08), (rh.x + 0.02, rh.y - 0.09, rh.z + 0.38 * s),
            mat=mat("Iron", "#3a3836", rough=0.4, metallic=0.9), parent=root, bevel=0.01)


def priest(root):
    b = body(root, h=1.76, build=1.0, skin="#e0bfa0", shirt="#efe9da", trousers="#efe9da", boots="#3a2a1e",
             hair="#d8d4cc", hair_style="short", skip_legs=True, eye="#3a4a5a")
    s = b["s"]
    robe = mat("Robe", "#efe9da", rough=0.9, noise_var=0.15, bump=0.2, bump_scale=30)
    gold = mat("Gold", "#d8b04a", rough=0.3, metallic=1.0)
    loft("Robe", [(0.0, 0.29 * s, 0.25 * s, 0, 0.0), (0.4 * s, 0.24 * s, 0.19 * s, 0, 0),
                  (0.9 * s, 0.18 * s, 0.13 * s, 0, 0), (1.2 * s, 0.18 * s, 0.12 * s, 0, 0),
                  (1.4 * s, 0.21 * s, 0.12 * s, 0, 0), (1.47 * s, 0.12 * s, 0.08 * s, 0, 0)], robe, root)
    for side in (-1, 1):
        lib.box(f"Stole{side}", (0.06 * s, 0.02, 1.0 * s), (side * 0.08 * s, -0.17 * s, 0.95 * s), mat=gold,
                parent=root)
    sun = lib.primitive("cylinder", "Sun", mat=gold, parent=root, vertices=24, radius=0.06 * s, depth=0.015,
                        location=(0, -0.2 * s, 1.25 * s))
    sun.rotation_euler = (math.radians(90), 0, 0)
    rh = b["hands"][1]
    lib.cylinder_between("Crozier", (rh.x + 0.02, rh.y - 0.02, 0.02), (rh.x + 0.04, rh.y - 0.04, 1.9 * s), 0.02,
                         mat=mat("Wood", "#6a4a2a", rough=0.6), parent=root, sides=10)
    disc = lib.primitive("cylinder", "Crest", mat=gold, parent=root, vertices=24, radius=0.09 * s, depth=0.02,
                         location=(rh.x + 0.04, rh.y - 0.04, 1.98 * s))
    disc.rotation_euler = (math.radians(90), 0, 0)


def noble(root):
    b = body(root, h=1.8, build=1.05, skin="#e2b894", shirt="#7a1e1e", trousers="#2a2420", boots="#1e1814",
             hair="#5a4632", hair_style="short", eye="#3a3020")
    s = b["s"]
    cloak = mat("Cloak", "#8e2424", rough=0.85, noise_var=0.2, bump=0.25, bump_scale=25)
    loft("Cloak", [(0.35 * s, 0.27 * s, 0.2 * s, 0, 0.05 * s), (0.8 * s, 0.24 * s, 0.17 * s, 0, 0.04 * s),
                   (1.2 * s, 0.22 * s, 0.14 * s, 0, 0.02 * s), (1.42 * s, 0.25 * s, 0.13 * s, 0, 0.01 * s),
                   (1.48 * s, 0.14 * s, 0.1 * s, 0, 0.01 * s)], cloak, root, cap=False)
    fur = mat("Fur", "#d8ccb4", rough=1.0, bump=0.8, bump_scale=200)
    loft("Collar", [(1.42 * s, 0.24 * s, 0.15 * s, 0, 0), (1.5 * s, 0.17 * s, 0.12 * s, 0, 0)], fur, root)
    gold = mat("Gold", "#d8b04a", rough=0.3, metallic=1.0)
    for i in range(7):
        a = math.pi * (1.15 + 0.7 * i / 6)
        sphere(f"Chain{i}", (math.cos(a) * 0.13 * s, -0.12 * s + math.sin(a) * 0.0, 1.32 * s + math.sin(a) * 0.06 * s),
               (0.018 * s,) * 3, gold, root, 8)
    hc = b["head"]
    hat = mat("Hat", "#2a2420", rough=0.8)
    lib.primitive("cylinder", "Hat", mat=hat, parent=root, vertices=24, radius=0.115 * s, depth=0.06 * s,
                  location=(hc.x, hc.y, hc.z + 0.1 * s))


def villager_woman(root):
    b = body(root, h=1.66, build=0.92, skin="#e6c09c", shirt="#6a7a4a", trousers="#5a4a3a", boots="#3a2a1e",
             hair="#6a3a1e", hair_style="long", skip_legs=True, eye="#3a4a2a")
    s = b["s"]
    skirt(root, s, "#5a4a6a")
    apron(root, s, "#d8cfb6", top=0.9, bottom=0.12, width=0.32, y=-0.2)
    hc = b["head"]
    scarf = mat("Scarf", "#a85a3a", rough=0.9, noise_var=0.2)
    sphere("Kerchief", hc + Vector((0, 0.02 * s, 0.05 * s)), (0.108 * s, 0.115 * s, 0.1 * s), scarf, root, 20)
    rh = b["hands"][1]
    basket = mat("Basket", "#a07a44", rough=0.9, bump=0.6, bump_scale=120)
    lib.primitive("cylinder", "Basket", mat=basket, parent=root, vertices=16, radius=0.12, depth=0.12,
                  location=(rh.x + 0.05, rh.y - 0.02, rh.z - 0.06))
    herbs = mat("Herbs", "#4a6a2a", rough=0.9)
    sphere("Herbs", (rh.x + 0.05, rh.y - 0.02, rh.z + 0.01), (0.1, 0.1, 0.05), herbs, root, 12)


def villager_man(root):
    b = body(root, h=1.76, build=1.1, skin="#d0a07a", shirt="#7a6a4a", trousers="#4a4234", boots="#3a2a1e",
             hair="#6a5030", hair_style="short", eye="#3a3020")
    s = b["s"]
    apron(root, s, "#cfc7b2", top=1.15, bottom=0.5, width=0.38, y=-0.16)
    hc = b["head"]
    cap = mat("Cap", "#4a4a3a", rough=0.9, noise_var=0.2)
    sphere("Cap", hc + Vector((0, 0.01 * s, 0.06 * s)), (0.105 * s, 0.112 * s, 0.075 * s), cap, root, 20)


# --------------------------------------------------------------------------
# Foes
# --------------------------------------------------------------------------

def _hood(root, b, color, mask=None):
    s, hc = b["s"], b["head"]
    cloth = mat("Hood" + color, color, rough=0.95, noise_var=0.25, bump=0.3, bump_scale=25)
    sphere("Hood", hc + Vector((0, 0.03 * s, 0.025 * s)), (0.128 * s, 0.13 * s, 0.14 * s), cloth, root, 20)
    loft("Mantle", [(1.32 * s, 0.25 * s, 0.17 * s, 0, 0.01 * s), (1.46 * s, 0.2 * s, 0.14 * s, 0, 0.01 * s),
                    (1.53 * s, 0.11 * s, 0.09 * s, 0, 0.01 * s)], cloth, root)
    if mask:
        scarf = mat("Mask" + mask, mask, rough=0.9)
        sphere("Mask", hc + Vector((0, -0.04 * s, -0.055 * s)), (0.088 * s, 0.08 * s, 0.055 * s), scarf, root, 16)


def _jerkin(root, s, color):
    leather = mat("Jerkin", color, rough=0.6, noise_var=0.25, bump=0.4, bump_scale=60)
    loft("Jerkin", [(0.78 * s, 0.19 * s, 0.13 * s, 0, 0), (1.0 * s, 0.18 * s, 0.125 * s, 0, 0),
                    (1.25 * s, 0.205 * s, 0.13 * s, 0, 0), (1.4 * s, 0.215 * s, 0.12 * s, 0, 0)], leather, root)
    belt = mat("Belt", "#2a1c12", rough=0.6)
    loft("Belt", [(0.9 * s, 0.2 * s, 0.14 * s, 0, 0), (0.95 * s, 0.2 * s, 0.14 * s, 0, 0)], belt, root)


def _bow(root, hand, s, wood_color="#5a3a1e"):
    """A short bow held upright in `hand`, string towards the body."""
    wood = mat("Bow", wood_color, rough=0.6, noise_var=0.2)
    pts, radii = [], []
    for k in range(9):
        a = (k / 8.0 - 0.5) * 2.0  # -1 .. 1
        pts.append(Vector((hand.x, hand.y - 0.06 - 0.12 * (1 - a * a) * s, hand.z + a * 0.55 * s)))
        radii.append(0.016 if abs(a) < 0.3 else 0.011)
    limb("Bow", pts, radii, wood, root, sides=8)
    string = mat("String", "#d8d0b8", rough=0.8)
    lib.cylinder_between("BowString", pts[0], pts[-1], 0.004, mat=string, parent=root, sides=4)


def _quiver(root, s):
    leather = mat("Quiver", "#4a3020", rough=0.6)
    q = lib.cylinder_between("Quiver", (0.1 * s, 0.17 * s, 0.95 * s), (-0.05 * s, 0.2 * s, 1.45 * s), 0.055 * s,
                             mat=leather, parent=root, sides=10)
    fletch = mat("Fletching", "#c8c0a8", rough=0.9)
    for k in range(4):
        x = -0.04 * s + k * 0.02 * s
        lib.cylinder_between(f"Arrow{k}", (x, 0.2 * s, 1.4 * s), (x - 0.02, 0.21 * s, 1.58 * s), 0.008,
                             mat=fletch, parent=root, sides=4)
    _ = q


def _blade(root, hand, s, length=0.62, curve=0.0, name="Blade", steel_color="#b8bcc4"):
    """A sword in the hand, point down and forward; `curve` bends it (a scimitar)."""
    steel = mat(name + "Steel", steel_color, rough=0.25, metallic=1.0)
    pts, radii = [], []
    for k in range(6):
        f = k / 5.0
        pts.append(Vector((hand.x + 0.03, hand.y - 0.1 - f * 0.12 - curve * f * f * 0.2,
                           hand.z - 0.05 - f * length * s)))
        radii.append(0.022 * (1.0 - 0.6 * f) + 0.004)
    obj = limb(name, pts, radii, steel, root, sides=6)
    obj.scale = (1.0, 0.35, 1.0)
    hilt = mat(name + "Hilt", "#3a2a1a", rough=0.6)
    lib.box(name + "Guard", (0.14, 0.03, 0.025), (hand.x + 0.03, hand.y - 0.06, hand.z + 0.02), mat=steel, parent=root)
    lib.cylinder_between(name + "Grip", (hand.x + 0.03, hand.y - 0.05, hand.z + 0.02),
                         (hand.x + 0.03, hand.y - 0.03, hand.z + 0.13), 0.018, mat=hilt, parent=root, sides=6)


def bandit(root):
    b = body(root, h=1.76, build=1.05, skin="#c08a64", shirt="#5c4e3c", trousers="#3a342a", boots="#2a2018",
             hair="#2a1a10", hair_style="short", eye="#2a2018")
    s = b["s"]
    _jerkin(root, s, "#6a4a2c")
    _hood(root, b, "#6a2a22", mask="#2a2420")
    _blade(root, b["hands"][1], s, length=0.6, curve=0.9, name="Scimitar")


def bandit_archer(root):
    b = body(root, h=1.74, build=0.98, skin="#d0a07a", shirt="#4a4a34", trousers="#3a342a", boots="#2a2018",
             hair="#5a3a1e", hair_style="short", eye="#3a3020")
    s = b["s"]
    _jerkin(root, s, "#4a5a34")
    _hood(root, b, "#3a4a2c", mask="#2a2a22")
    _quiver(root, s)
    _bow(root, b["hands"][0], s)


def _skeleton_body(root, h=1.74):
    """A walking skeleton: bones instead of flesh, in the same POSE as body()."""
    s = h / 1.8
    bone = mat("Bone", "#d9d0b8", rough=0.65, bump=0.35, bump_scale=90, noise_var=0.12)
    dark = mat("Socket", "#14100c", rough=1.0)
    hip_z = 0.92 * s
    lows = [leg_pose(side, s)[3].z for side in (-1, 1)]
    POSE["lift"] = -min(lows) - hip_z + 0.07 * s
    for side in (-1, 1):
        x = side * 0.09 * s
        swing, bend, knee, ankle = leg_pose(side, s)
        hip = Vector((x, 0, hip_z))
        limb(f"Femur{side}", [hip, hip + knee], [0.028 * s, 0.024 * s], bone, root, sides=8)
        limb(f"Tibia{side}", [hip + knee, hip + ankle], [0.024 * s, 0.02 * s], bone, root, sides=8)
        toe = hip + ankle + _down(swing - bend * 0.4 + math.pi / 2) * 0.12 * s
        limb(f"FootBone{side}", [hip + ankle, toe], [0.022 * s, 0.016 * s], bone, root, sides=6)
    sphere("Pelvis", (0, 0, hip_z + 0.02 * s), (0.13 * s, 0.07 * s, 0.06 * s), bone, root)
    tilt = 0.012 * s * POSE["walk"]
    spine_top = Vector((0, -tilt, hip_z + 0.52 * s))
    limb("Spine", [Vector((0, 0.02 * s, hip_z)), Vector((0, 0.03 * s, hip_z + 0.25 * s)), spine_top],
         [0.025 * s, 0.022 * s, 0.022 * s], bone, root, sides=8)
    for k in range(5):  # ribcage
        z = hip_z + (0.24 + k * 0.06) * s
        w = (0.15 - abs(k - 2.4) * 0.012) * s
        rib = lib.primitive("torus", f"Rib{k}", mat=bone, parent=root, major_radius=1.0, minor_radius=0.012 / w * s,
                            location=(0, -tilt * 0.6, z))
        rib.scale = (w, w * 0.72, w)
    sh_z = hip_z + 0.48 * s
    lib.cylinder_between("Collar", (-0.2 * s, -tilt, sh_z + 0.02 * s), (0.2 * s, -tilt, sh_z + 0.02 * s), 0.018 * s,
                         mat=bone, parent=root, sides=6)
    hands = []
    for side in (-1, 1):
        phase = POSE["phase"] + (0.0 if side < 0 else math.pi)
        swing = -0.38 * math.sin(phase) * POSE["walk"]
        shoulder = Vector((side * 0.2 * s, -tilt, sh_z))
        elbow = shoulder + _down(swing) * 0.29 * s + Vector((side * 0.03 * s, 0, 0))
        hand = elbow + _down(swing + 0.2 + 0.25 * POSE["walk"]) * 0.27 * s
        limb(f"Humerus{side}", [shoulder, elbow], [0.022 * s, 0.019 * s], bone, root, sides=8)
        limb(f"Radius{side}", [elbow, hand], [0.019 * s, 0.016 * s], bone, root, sides=8)
        sphere(f"HandBone{side}", hand, (0.03 * s, 0.025 * s, 0.04 * s), bone, root, 8)
        hands.append(hand)
    head_c = spine_top + Vector((0, -0.02 * s, 0.17 * s))
    limb("Neck", [spine_top, head_c + Vector((0, 0, -0.08 * s))], [0.02 * s, 0.018 * s], bone, root, sides=6)
    sphere("Skull", head_c, (0.09 * s, 0.1 * s, 0.11 * s), bone, root, 20)
    sphere("Jaw", head_c + Vector((0, -0.035 * s, -0.075 * s)), (0.06 * s, 0.06 * s, 0.035 * s), bone, root, 12)
    for side in (-1, 1):
        sphere(f"EyeSocket{side}", head_c + Vector((side * 0.035 * s, -0.082 * s, 0.01 * s)),
               (0.024 * s, 0.02 * s, 0.026 * s), dark, root, 10)
        sphere(f"Glint{side}", head_c + Vector((side * 0.035 * s, -0.095 * s, 0.01 * s)), (0.006 * s,) * 3,
               mat("Glint", "#ff8a3a", emission="#ff6a1a", strength=8.0), root, 6)
    sphere("NoseHole", head_c + Vector((0, -0.095 * s, -0.025 * s)), (0.012 * s, 0.01 * s, 0.018 * s), dark, root, 8)
    return {"s": s, "hands": hands, "head": head_c, "hip_z": hip_z}


def skeleton(root):
    b = _skeleton_body(root)
    s = b["s"]
    rust = mat("Rust", "#6a4a32", rough=0.75, metallic=0.5, bump=0.6, bump_scale=200, noise_var=0.3)
    lib.box("BreastScrap", (0.22 * s, 0.04, 0.2 * s), (0.02 * s, -0.12 * s, 1.27 * s), mat=rust, parent=root,
            rotation=(0, math.radians(8), 0), bevel=0.01)
    helm = mat("Helm", "#5a5048", rough=0.5, metallic=0.7, bump=0.5, bump_scale=200)
    sphere("Helm", b["head"] + Vector((0, 0.01 * s, 0.045 * s)), (0.1 * s, 0.11 * s, 0.085 * s), helm, root, 18)
    rag = mat("Rag", "#4a3a2a", rough=1.0, noise_var=0.3)
    loft("Loincloth", [(0.68 * s, 0.13 * s, 0.09 * s, 0, 0), (0.92 * s, 0.14 * s, 0.09 * s, 0, 0)], rag, root, cap=False)
    _blade(root, b["hands"][1], s, length=0.5, name="Shortsword", steel_color="#8a8a84")


def skeleton_archer(root):
    b = _skeleton_body(root)
    s = b["s"]
    rag = mat("Rag", "#3a3428", rough=1.0, noise_var=0.3)
    loft("Loincloth", [(0.68 * s, 0.13 * s, 0.09 * s, 0, 0), (0.92 * s, 0.14 * s, 0.09 * s, 0, 0)], rag, root, cap=False)
    sphere("Cowl", b["head"] + Vector((0, 0.03 * s, 0.03 * s)), (0.115 * s, 0.12 * s, 0.12 * s), rag, root, 18)
    _quiver(root, s)
    _bow(root, b["hands"][0], s, "#3a2a1a")


def wolf(root):
    """A grey wolf trotting (diagonal legs move together). It faces -y like the
    other figures; the body is built from overlapping ellipsoids."""
    s = 0.92
    fur = mat("Fur", "#6e665a", rough=0.95, noise_var=0.3, bump=0.7, bump_scale=160)
    pale = mat("FurPale", "#aaa08c", rough=0.95, noise_var=0.25, bump=0.6, bump_scale=160)
    dark = mat("FurDark", "#3a352e", rough=0.95, bump=0.5, bump_scale=160)
    nose = mat("Nose", "#141210", rough=0.3)
    eye = mat("WolfEye", "#d8a83a", rough=0.2, emission="#8a5a10", strength=1.5)
    walk = POSE["walk"]
    shoulder_z, hip_z = 0.62 * s, 0.6 * s
    bob = 0.02 * s * abs(math.sin(POSE["phase"])) * walk
    legs = []
    for front, y in ((True, -0.36 * s), (False, 0.38 * s)):
        for side in (-1, 1):
            phase = POSE["phase"] + (0.0 if (side < 0) == front else math.pi)
            swing = 0.45 * math.sin(phase) * walk
            bend = walk * (0.15 + 0.5 * max(0.0, math.cos(phase)))
            top = Vector((side * 0.09 * s, y, (shoulder_z if front else hip_z) + bob))
            upper = 0.28 * s
            lower = 0.3 * s
            k_sign = -1.0 if front else 1.0  # elbows bend back, hocks forward
            knee = top + _down(swing + k_sign * 0.1) * upper
            paw = knee + _down(swing - k_sign * bend) * lower
            legs.append(paw.z)
            limb(f"Upper{front}{side}", [top, knee], [0.06 * s, 0.04 * s], fur, root, sides=10)
            limb(f"Lower{front}{side}", [knee, paw], [0.035 * s, 0.028 * s], fur if front else dark, root, sides=8)
            sphere(f"Paw{front}{side}", paw + Vector((0, -0.03 * s, 0.01 * s)), (0.04 * s, 0.055 * s, 0.025 * s),
                   dark, root, 10)
    POSE["lift"] = -min(legs) + 0.025 * s
    # Body: chest, ribs, loins and haunches.
    sphere("Chest", (0, -0.3 * s, 0.68 * s + bob), (0.15 * s, 0.22 * s, 0.17 * s), fur, root, 20)
    sphere("Ribs", (0, -0.02 * s, 0.69 * s + bob), (0.145 * s, 0.32 * s, 0.145 * s), fur, root, 20)
    sphere("Haunch", (0, 0.3 * s, 0.67 * s + bob), (0.135 * s, 0.2 * s, 0.145 * s), fur, root, 18)
    sphere("Back", (0, 0.05 * s, 0.76 * s + bob), (0.11 * s, 0.42 * s, 0.07 * s), dark, root, 16)
    sphere("Belly", (0, -0.08 * s, 0.6 * s + bob), (0.1 * s, 0.26 * s, 0.07 * s), pale, root, 16)
    ruff = mat("FurRuff", "#8a8272", rough=0.95, noise_var=0.3, bump=0.8, bump_scale=160)
    sphere("Ruff", (0, -0.38 * s, 0.75 * s + bob), (0.15 * s, 0.13 * s, 0.15 * s), ruff, root, 18)
    # Neck and head, carried low and forward.
    head = Vector((0, -0.62 * s, 0.82 * s + bob))
    limb("Neck", [Vector((0, -0.38 * s, 0.78 * s + bob)), head + Vector((0, 0.05 * s, -0.02 * s))],
         [0.1 * s, 0.075 * s], fur, root, sides=12)
    sphere("Head", head, (0.085 * s, 0.1 * s, 0.08 * s), fur, root, 18)
    snout_tip = head + Vector((0, -0.19 * s, -0.035 * s))
    limb("Snout", [head + Vector((0, -0.06 * s, -0.01 * s)), snout_tip], [0.055 * s, 0.03 * s], pale, root, sides=10)
    sphere("Nose", snout_tip + Vector((0, -0.01 * s, 0.01 * s)), (0.022 * s, 0.02 * s, 0.018 * s), nose, root, 10)
    for side in (-1, 1):
        ear = lib.primitive("cone", f"Ear{side}", mat=dark, parent=root, vertices=8, radius1=0.035 * s, radius2=0.004,
                            depth=0.09 * s, location=(side * 0.05 * s, head.y + 0.02 * s, head.z + 0.09 * s))
        ear.rotation_euler = (math.radians(-12), math.radians(side * 14), 0)
        sphere(f"WolfEye{side}", head + Vector((side * 0.042 * s, -0.07 * s, 0.025 * s)), (0.012 * s,) * 3, eye, root, 8)
    # Tail, hanging with a little sway.
    sway = 0.05 * math.sin(POSE["phase"] * 2) * walk
    base = Vector((0, 0.46 * s, 0.7 * s + bob))
    limb("Tail", [base, base + Vector((sway, 0.12 * s, -0.12 * s)), base + Vector((sway * 2, 0.18 * s, -0.32 * s))],
         [0.045 * s, 0.05 * s, 0.025 * s], fur, root, sides=10)


CHARACTERS = {
    "fighter": fighter,
    "wizard": wizard,
    "cleric": cleric,
    "rogue": rogue,
    "innkeeper": innkeeper,
    "smith": smith,
    "priest": priest,
    "noble": noble,
    "villager_woman": villager_woman,
    "villager_man": villager_man,
    "bandit": bandit,
    "bandit_archer": bandit_archer,
    "skeleton": skeleton,
    "skeleton_archer": skeleton_archer,
    "wolf": wolf,
}


def build(name, yaw, phase, walk):
    """Builds one pose of a character; returns its root."""
    POSE["phase"], POSE["walk"], POSE["lift"] = phase, walk, 0.0
    root = setup(yaw)
    CHARACTERS[name](root)
    root.location.z = POSE["lift"] * HERO_SCALE
    bpy.context.view_layer.update()
    return root


def frames():
    """(column, phase, walk) for idle + walk cycle."""
    out = [(0, 0.0, 0.0)]
    for k in range(WALK_FRAMES):
        out.append((k + 1, 2 * math.pi * k / WALK_FRAMES, 1.0))
    return out


def cell_bounds(name):
    """Camera-plane bounds (metres, relative to the feet) over every pose."""
    xmax, ymin, ymax = 0.0, 0.0, 0.0
    rot = Euler((math.pi / 2 - lib.ELEVATION, 0, 0)).to_matrix()
    inv = rot.inverted()
    for _, yaw in DIRECTIONS:
        for _, phase, walk in frames():
            build(name, yaw, phase, walk)
            objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
            pts = lib.mesh_points(objs)
            local = np.array([inv @ Vector(p) for p in pts])
            xmax = max(xmax, np.abs(local[:, 0]).max())
            ymin = min(ymin, local[:, 1].min())
            ymax = max(ymax, local[:, 1].max())
    return xmax, ymin, ymax


def fixed_camera(xmax, ymin, ymax, margin_px=3):
    """Ortho camera with the feet (world origin) at the same pixel for every pose."""
    s = lib.PX_PER_M
    half_w = int(math.ceil(xmax * s)) + margin_px
    top = int(math.ceil(ymax * s)) + margin_px
    bottom = int(math.ceil(-ymin * s)) + margin_px
    res = (2 * half_w, top + bottom)
    rot = Euler((math.pi / 2 - lib.ELEVATION, 0, 0))
    data = bpy.data.cameras.new("Camera")
    data.type = 'ORTHO'
    cam = bpy.data.objects.new("Camera", data)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    cam.rotation_euler = rot
    center_local = Vector((0.0, (top - bottom) / 2 / s, 60.0))
    cam.location = rot.to_matrix() @ center_local
    data.ortho_scale = max(res) / s
    data.clip_end = 400
    sc = bpy.context.scene
    sc.render.resolution_x = res[0] * lib.SUPERSAMPLE
    sc.render.resolution_y = res[1] * lib.SUPERSAMPLE
    return res, (half_w, top)


def render_sheet(name):
    """Renders every facing and frame into one sheet plus its JSON description."""
    from PIL import Image
    bounds = cell_bounds(name)
    tmp = lib.ASSETS / "characters" / f".{name}_frame.png"
    cells = {}
    res = origin = None
    for row, (dir_name, yaw) in enumerate(DIRECTIONS):
        for col, phase, walk in frames():
            build(name, yaw, phase, walk)
            res, origin = fixed_camera(*bounds)
            cells[(row, col)] = lib.render(tmp, res=res).copy()
    tmp.unlink(missing_ok=True)
    n_cols = 1 + WALK_FRAMES
    sheet = Image.new("RGBA", (res[0] * n_cols, res[1] * len(DIRECTIONS)), (0, 0, 0, 0))
    for (row, col), img in cells.items():
        sheet.paste(img, (col * res[0], row * res[1]))
    sheet_path = lib.ASSETS / "characters" / f"{name}_sheet.png"
    sheet.save(sheet_path)
    # The south-east idle frame doubles as the class's static sprite.
    cells[(1, 0)].save(lib.ASSETS / "characters" / f"{name}.png")
    anim = {
        "texture": f"res://assets/characters/{name}_sheet.png",
        "cell": list(res),
        "origin": list(origin),
        "directions": [d for d, _ in DIRECTIONS],
        "columns": n_cols,
        "idle_column": 0,
        "walk_columns": list(range(1, n_cols)),
        "cycle_px": 110,
    }
    (lib.ASSETS / "characters" / f"{name}_anim.json").write_text(json.dumps(anim, indent="\t") + "\n")
    print("wrote", sheet_path, sheet.size, "cell", res, "feet", origin)
    return list(origin)


def update_sheets(origins):
    """Points every character sheet using a class sprite at its animation, and
    stores the static sprite's feet pixel."""
    for path in sorted((lib.ROOT / "data" / "characters").glob("*.json")):
        data = json.loads(path.read_text())
        sprite = data.get("art", {}).get("sprite", "")
        for name, origin in origins.items():
            if sprite.endswith(f"/characters/{name}.png"):
                data["art"]["sprite_origin"] = origin
                data["art"]["animation"] = f"res://assets/characters/{name}_anim.json"
                path.write_text(json.dumps(data, indent="\t") + "\n")
                print("updated", path.name)


def run(names=None):
    origins = {}
    for name in names or CHARACTERS:
        origins[name] = render_sheet(name)
    update_sheets(origins)
