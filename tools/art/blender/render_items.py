"""Inventory icons, pre-rendered like the world art.

Each item is a small procedural model lit by a studio rig (key light from the
upper left, a warm fill and a cool rim) and rendered on a transparent
background, then given a soft drop shadow so it reads on the dark slots.
Long items (weapons) lie diagonally, the way classic RPG inventories show
them; upright items (potions, boots, armour) stand facing the viewer.

Output: assets/items/<name>.png, 64x64 (rendered at 4x and downscaled).
"""
import math

import bpy
import numpy as np
from mathutils import Euler, Vector
from PIL import Image, ImageFilter

import lib

SIZE = 64
RENDER = 256
SAMPLES = 48


# --------------------------------------------------------------------------
# Scene, lights and framing
# --------------------------------------------------------------------------

def setup():
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=(0.32, 0.34, 0.38), sky_strength=0.6)
    for name, loc, energy, color, size in (
            ("Key", (-3.0, -3.5, 5.0), 900.0, (1.0, 0.95, 0.86), 2.5),
            ("Fill", (4.0, -2.5, 2.0), 260.0, (1.0, 0.85, 0.7), 3.0),
            ("Rim", (1.5, 4.0, 3.5), 520.0, (0.75, 0.85, 1.0), 2.0)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy
        data.color = color
        data.size = size
        obj = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    root = bpy.data.objects.new("Item", None)
    bpy.context.scene.collection.objects.link(root)
    return root


def frame(elevation_deg, margin=0.1):
    """Square ortho camera looking north at `elevation_deg`, fitted to the meshes."""
    data = bpy.data.cameras.new("Camera")
    data.type = 'ORTHO'
    cam = bpy.data.objects.new("Camera", data)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    cam.rotation_euler = Euler((math.radians(90 - elevation_deg), 0, 0))
    bpy.context.view_layer.update()
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    pts = lib.mesh_points(objs)
    rot = cam.rotation_euler.to_matrix()
    inv = rot.inverted()
    local = np.array([inv @ Vector(p) for p in pts])
    lo, hi = local.min(axis=0), local.max(axis=0)
    extent = max(hi[0] - lo[0], hi[1] - lo[1]) * (1 + 2 * margin)
    center = Vector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, hi[2] + 10.0))
    cam.location = rot @ center
    data.ortho_scale = extent
    data.clip_end = 100
    sc = bpy.context.scene
    sc.render.resolution_x = RENDER
    sc.render.resolution_y = RENDER
    sc.render.resolution_percentage = 100


def finish(name, elevation=60):
    frame(elevation)
    path = lib.ASSETS / "items" / f"{name}.png"
    img = lib.render(path)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    # Soft drop shadow down-right, under the item.
    a = img.split()[3]
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(a.point(lambda v: int(v * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(1.6))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(shadow, (2, 2))
    out.alpha_composite(img)
    out.save(path)
    print("wrote", path)


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

def steel(name="Steel", color="#c4c8ce", rough=0.28):
    return lib.material(name, lib.lin(color), rough=rough, metallic=1.0, noise_var=0.12, noise_scale=30, bump=0.05)


def iron(name="Iron"):
    return lib.material(name, lib.lin("#4a4744"), rough=0.5, metallic=0.85, noise_var=0.25, noise_scale=20, bump=0.2)


def brass(name="Brass", color="#c99a3e"):
    return lib.material(name, lib.lin(color), rough=0.3, metallic=1.0, noise_var=0.1, noise_scale=25)


def gold_mat(name="Gold"):
    return lib.material(name, lib.lin("#e2b24a"), rough=0.22, metallic=1.0, noise_var=0.08, noise_scale=40)


def leather(name="Leather", color="#6b4528"):
    return lib.material(name, lib.lin(color), rough=0.7, noise_var=0.3, noise_scale=12, bump=0.35, bump_scale=60)


def wood(name="Wood", color="#7a5534"):
    return lib.material(name, lib.lin(color), rough=0.65, noise_var=0.35, noise_scale=4, bump=0.2, bump_scale=30)


def cloth(name, color, bump=0.25):
    return lib.material(name, lib.lin(color), rough=0.95, noise_var=0.2, noise_scale=20, bump=bump, bump_scale=80)


def glass(name="Glass", color="#dfe8e6"):
    return lib.material(name, lib.lin(color), rough=0.04, spec=0.8, transmission=1.0)


def liquid(name, color, glow=0.4):
    return lib.material(name, lib.lin(color), rough=0.1, transmission=0.6, emission=lib.lin(color),
                        emission_strength=glow)


def chainmail(name="Mail", color="#9ea3a9"):
    """Metal with a Voronoi ring bump: reads as mail at icon size."""
    mat = lib.material(name, lib.lin(color), rough=0.35, metallic=1.0)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = 'DISTANCE_TO_EDGE'
    vor.inputs["Scale"].default_value = 45.0
    nt.links.new(coord.outputs["Object"], vor.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.9
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def blade(name, length, width, thick, mat, parent, x0=0.0, tip=0.18):
    """Flat double-edged blade along +x, with a tapered point and a ridge."""
    hw, ht = width / 2, thick / 2
    body = length * (1 - tip)
    v = [(x0, -hw, 0), (x0 + body, -hw * 0.92, 0), (x0 + length, 0, 0), (x0 + body, hw * 0.92, 0), (x0, hw, 0),
         (x0, 0, ht), (x0 + body, 0, ht * 0.9), (x0, 0, -ht), (x0 + body, 0, -ht * 0.9)]
    f = [(0, 1, 6, 5), (1, 2, 6), (2, 3, 6), (3, 4, 5, 6),
         (0, 5, 4), (0, 7, 8, 1), (1, 8, 2), (2, 8, 3), (3, 8, 7, 4), (0, 4, 7)]
    return lib.mesh_object(name, v, f, mat=mat, parent=parent)


def grip(name, x0, x1, r, mat, parent):
    return lib.cylinder_between(name, (x0, 0, 0), (x1, 0, 0), r, mat=mat, parent=parent, sides=12)


def sphere(name, loc, r, mat, parent, scale=(1, 1, 1), seg=24):
    o = lib.primitive("uv_sphere", name, mat=mat, parent=parent, radius=r, location=loc, segments=seg,
                      ring_count=seg // 2)
    o.scale = scale
    bpy.ops.object.shade_smooth()
    return o


def cyl(name, loc, r, depth, mat, parent, rot=(0, 0, 0), verts=24, scale=(1, 1, 1)):
    o = lib.primitive("cylinder", name, mat=mat, parent=parent, radius=r, depth=depth, location=loc,
                      vertices=verts)
    o.rotation_euler = rot
    o.scale = scale
    return o


def torus(name, loc, major, minor, mat, parent, rot=(0, 0, 0)):
    o = lib.primitive("torus", name, mat=mat, parent=parent, major_radius=major, minor_radius=minor,
                      location=loc, major_segments=40, minor_segments=12)
    o.rotation_euler = rot
    bpy.ops.object.shade_smooth()
    return o


def diagonal(root, angle=40):
    root.rotation_euler = (0, 0, math.radians(angle))


def lathe(name, profile, mat, parent, sides=32, loc=(0, 0, 0)):
    """Surface of revolution around z from (radius, z) pairs."""
    verts, faces = [], []
    for z_i, (r, z) in enumerate(profile):
        for s in range(sides):
            a = 2 * math.pi * s / sides
            verts.append((loc[0] + r * math.cos(a), loc[1] + r * math.sin(a), loc[2] + z))
    for i in range(len(profile) - 1):
        for s in range(sides):
            a, b = i * sides + s, i * sides + (s + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    o = lib.mesh_object(name, verts, faces, mat=mat, parent=parent, smooth=True)
    return o


# --------------------------------------------------------------------------
# Weapons
# --------------------------------------------------------------------------

def sword(name, blade_len, guard_w, grip_len, blade_w=0.05):
    root = setup()
    st = steel()
    blade(name + "Blade", blade_len, blade_w, 0.012, st, root)
    lib.box("Guard", (0.035, guard_w, 0.03), (-0.01, 0, 0), mat=brass(), parent=root, bevel=0.008)
    grip("Grip", -0.02, -grip_len, 0.016, leather("Wrap", "#3b2616"), root)
    sphere("Pommel", (-grip_len - 0.02, 0, 0), 0.027, brass(), root)
    diagonal(root)
    finish(name, elevation=72)


def longsword():
    sword("longsword", 0.85, 0.2, 0.2)


def shortsword():
    sword("shortsword", 0.55, 0.16, 0.13, blade_w=0.048)


def dagger():
    sword("dagger", 0.26, 0.1, 0.1, blade_w=0.035)


def rapier():
    root = setup()
    st = steel()
    blade("RapierBlade", 0.9, 0.022, 0.008, st, root)
    br = brass()
    lib.box("Quillons", (0.02, 0.16, 0.02), (-0.01, 0, 0), mat=br, parent=root, bevel=0.005)
    torus("Guard", (0.0, 0.0, 0.0), 0.05, 0.006, br, root, rot=(0, math.radians(90), 0))
    torus("Knuckle", (-0.06, -0.035, 0), 0.06, 0.005, br, root, rot=(math.radians(90), 0, 0))
    grip("Grip", -0.02, -0.12, 0.014, leather("Wrap", "#2a1a10"), root)
    sphere("Pommel", (-0.14, 0, 0), 0.024, br, root)
    diagonal(root)
    finish("rapier", elevation=72)


def greataxe():
    root = setup()
    grip("Haft", -0.55, 0.45, 0.02, wood("Haft", "#5a3f26"), root)
    grip("Wrap", -0.55, -0.35, 0.024, leather(), root)
    st = steel("AxeSteel", "#a8acb2", 0.33)
    for side in (-1, 1):
        lib.mesh_object(f"Bit{side}", [(0.34, 0, 0), (0.46, 0, 0), (0.5, side * 0.2, 0), (0.3, side * 0.2, 0)],
                        [(0, 1, 2, 3)], mat=st, parent=root).modifiers.new("T", 'SOLIDIFY').thickness = 0.02
    cyl("Socket", (0.4, 0, 0), 0.03, 0.14, st, root, rot=(0, math.radians(90), 0))
    diagonal(root)
    finish("greataxe", elevation=72)


def mace():
    root = setup()
    grip("Shaft", -0.35, 0.3, 0.017, wood("Haft", "#5a3f26"), root)
    grip("Wrap", -0.35, -0.2, 0.02, leather(), root)
    ir = iron()
    cyl("Head", (0.36, 0, 0), 0.035, 0.14, ir, root, rot=(0, math.radians(90), 0))
    for i in range(6):
        a = math.tau * i / 6
        lib.box(f"Flange{i}", (0.12, 0.012, 0.05), (0.36, math.cos(a) * 0.045, math.sin(a) * 0.045), mat=ir,
                parent=root, rotation=(a, 0, 0), bevel=0.004)
    sphere("Cap", (0.44, 0, 0), 0.025, ir, root)
    diagonal(root)
    finish("mace", elevation=70)


def quarterstaff():
    root = setup()
    grip("Staff", -0.8, 0.8, 0.038, wood("Ash", "#8a6a44"), root)
    ir = iron()
    for x in (-0.8, 0.8):
        cyl(f"Cap{x}", (x, 0, 0), 0.043, 0.1, ir, root, rot=(0, math.radians(90), 0))
    grip("Wrap", -0.12, 0.12, 0.043, leather("Wrap", "#4a3020"), root)
    diagonal(root)
    finish("quarterstaff", elevation=74)


def warhammer():
    root = setup()
    grip("Shaft", -0.4, 0.28, 0.016, wood("Haft", "#5a3f26"), root)
    grip("Wrap", -0.4, -0.22, 0.019, leather(), root)
    st = steel("HammerSteel", "#a8acb2", 0.35)
    lib.box("Head", (0.07, 0.09, 0.07), (0.3, 0.03, 0), mat=st, parent=root, bevel=0.01)
    lib.mesh_object("Spike", [(0.27, -0.015, -0.02), (0.33, -0.015, -0.02), (0.33, -0.015, 0.02),
                              (0.27, -0.015, 0.02), (0.3, -0.13, 0)],
                    [(0, 1, 2, 3), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], mat=st, parent=root)
    diagonal(root)
    finish("warhammer", elevation=70)


def shortbow():
    root = setup()
    bow = wood("Yew", "#8a5a2e")
    pts = []
    for i in range(25):
        t = i / 24 * 2 - 1  # -1..1 along the bow
        pts.append(Vector((t * 0.55, -0.08 * (1 - t * t) - 0.03 * abs(t) ** 3, 0)))
    # Recurved tips.
    for i in range(len(pts) - 1):
        r = 0.026 * (1 - 0.45 * abs(i / 12 - 1))
        lib.cylinder_between(f"Limb{i}", pts[i], pts[i + 1], r, mat=bow, parent=root, sides=8)
    grip("Grip", -0.06, 0.06, 0.02, leather("BowGrip", "#3b2616"), root).location = (0, -0.08, 0)
    lib.cylinder_between("String", pts[0], pts[-1], 0.006, mat=cloth("String", "#d8cfb8"), parent=root, sides=6)
    root.rotation_euler = (0, 0, math.radians(40))
    finish("shortbow", elevation=74)


def arrow(name, root, y, z):
    shaft = wood("Shaft%s" % name, "#a8875a")
    lib.cylinder_between(name, (-0.35, y, z), (0.32, y, z), 0.006, mat=shaft, parent=root, sides=8)
    lib.mesh_object(name + "Head", [(0.32, y - 0.012, z), (0.32, y + 0.012, z), (0.38, y, z)],
                    [(0, 1, 2)], mat=iron(), parent=root)
    feather = cloth("Fletch", "#e8e2d4")
    for s in (-1, 1):
        lib.mesh_object(name + f"F{s}", [(-0.34, y, z), (-0.22, y, z), (-0.25, y + s * 0.025, z + 0.01),
                                         (-0.34, y + s * 0.022, z + 0.01)],
                        [(0, 1, 2, 3)], mat=feather, parent=root)


def arrows():
    root = setup()
    for i, (y, z) in enumerate(((-0.03, 0), (0, 0.012), (0.03, 0))):
        arrow(f"Arrow{i}", root, y, z)
    lib.box("Tie", (0.03, 0.09, 0.03), (-0.05, 0, 0.005), mat=leather("Tie", "#5a3a22"), parent=root)
    diagonal(root)
    finish("arrows", elevation=70)


# --------------------------------------------------------------------------
# Armour and clothing
# --------------------------------------------------------------------------

def torso(name, mat, parent, length=0.62, flare=1.0):
    """A cuirass/tunic body: a lathe flattened front-to-back, with shoulders."""
    prof = [(0.06, length + 0.02), (0.15, length), (0.2, length - 0.08), (0.19, length - 0.25),
            (0.17, length - 0.4), (0.18 * flare, 0.08), (0.2 * flare, 0.0)]
    o = lathe(name, prof, mat, parent)
    o.scale = (1.0, 0.55, 1.0)
    for s in (-1, 1):
        sh = sphere(f"{name}Shoulder{s}", (s * 0.2, 0, length - 0.1), 0.085, mat, parent, scale=(1.0, 0.8, 0.7))
        cyl(f"{name}Sleeve{s}", (s * 0.27, 0, length - 0.2), 0.065, 0.2, mat, parent, rot=(0, math.radians(s * 25), 0))
        sh.name = sh.name
    return o


def leather_armor():
    root = setup()
    lth = leather("Leather", "#7a4f2c")
    torso("Cuirass", lth, root)
    strap = leather("Strap", "#3b2616")
    for z in (0.18, 0.3):
        lib.box(f"Strap{z}", (0.4, 0.23, 0.025), (0, 0, z), mat=strap, parent=root)
    finish("leather", elevation=18)


def studded_leather():
    root = setup()
    lth = leather("Leather", "#5e3c22")
    torso("Cuirass", lth, root)
    stud = brass("Stud", "#b0a080")
    for row in range(5):
        for col in range(5):
            x = (col - 2) * 0.065
            z = 0.12 + row * 0.08
            sphere(f"Stud{row}{col}", (x, -0.098 - 0.01 * (1 - abs(x) * 4), z), 0.011, stud, root, seg=8)
    finish("studded_leather", elevation=18)


def chain_shirt():
    root = setup()
    torso("Shirt", chainmail("Mail"), root, length=0.55)
    lib.box("Collar", (0.18, 0.12, 0.04), (0, 0, 0.56), mat=leather("Collar", "#4a3020"), parent=root, bevel=0.01)
    finish("chain_shirt", elevation=18)


def chain_mail():
    root = setup()
    torso("Hauberk", chainmail("Mail", "#8f949a"), root, length=0.72, flare=1.25)
    lib.box("Belt", (0.4, 0.24, 0.05), (0, 0, 0.3), mat=leather("Belt", "#3b2616"), parent=root)
    lib.box("Buckle", (0.05, 0.02, 0.05), (0, -0.125, 0.3), mat=brass(), parent=root)
    finish("chain_mail", elevation=18)


def shield():
    root = setup()
    wd = wood("Planks", "#6e4a2a")
    disc = cyl("Disc", (0, 0, 0), 0.3, 0.03, wd, root, rot=(math.radians(90), 0, 0), verts=48)
    ir = iron()
    torus("Rim", (0, 0, 0), 0.3, 0.014, ir, root, rot=(math.radians(90), 0, 0))
    sphere("Boss", (0, -0.02, 0), 0.08, steel("Boss", "#a8acb2", 0.35), root, scale=(1, 0.6, 1))
    paint = lib.material("Paint", lib.lin("#a8342a"), rough=0.8, noise_var=0.3, noise_scale=10)
    for a in (45, 135):
        lib.box(f"Band{a}", (0.07, 0.008, 0.56), (0, -0.019, 0), mat=paint, parent=root,
                rotation=(0, math.radians(a), 0))
    disc.name = "Disc"
    finish("shield", elevation=20)


def iron_helm():
    root = setup()
    st = steel("Helm", "#9ea2a8", 0.35)
    prof = [(0.001, 0.17), (0.05, 0.165), (0.09, 0.145), (0.115, 0.11), (0.13, 0.06), (0.135, 0.01),
            (0.137, 0.0)]
    lathe("Dome", prof, st, root)
    torus("Band", (0, 0, 0.012), 0.137, 0.014, iron(), root)
    lib.box("Nasal", (0.03, 0.012, 0.09), (0, -0.139, -0.025), mat=st, parent=root, bevel=0.005)
    for k in range(10):
        a = math.tau * k / 10
        sphere(f"Rivet{k}", (math.cos(a) * 0.139, math.sin(a) * 0.139, 0.012), 0.008, iron("Rivet"), root, seg=8)
    finish("iron_helm", elevation=22)


def cloak_of_protection():
    root = setup()
    green = cloth("Cloak", "#2c5a3a", bump=0.4)
    n = 24
    verts, faces = [], []
    for j in range(n + 1):
        z = 0.7 * (1 - j / n)
        w = 0.14 + 0.28 * (j / n)
        for i in range(n + 1):
            t = i / n * 2 - 1
            x = t * w
            y = 0.04 * math.sin(t * math.pi * 3 + j * 0.2) * (j / n) - 0.05 * (1 - t * t)
            verts.append((x, y, z))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    cl = lib.mesh_object("Cloak", verts, faces, mat=green, parent=root, smooth=True)
    sol = cl.modifiers.new("Thick", 'SOLIDIFY')
    sol.thickness = 0.012
    lib.box("Hem", (0.3, 0.02, 0.04), (0, -0.05, 0.7), mat=cloth("Hem", "#1f4029"), parent=root)
    sphere("Clasp", (0, -0.07, 0.69), 0.03, gold_mat(), root, scale=(1, 0.5, 1))
    finish("cloak_of_protection", elevation=15)


def ring_of_protection():
    root = setup()
    torus("Band", (0, 0, 0), 0.1, 0.022, steel("Silver", "#d6d8dc", 0.2), root, rot=(math.radians(70), 0, 0))
    gem = lib.primitive("ico_sphere", "Gem", mat=liquid("Sapphire", "#2a5ad8", glow=0.6), parent=root,
                        radius=0.04, subdivisions=1, location=(0, -0.03, 0.12))
    gem.scale = (1, 1, 0.7)
    cyl("Setting", (0, -0.025, 0.1), 0.03, 0.03, steel("Silver2", "#d6d8dc", 0.2), root, verts=16)
    finish("ring_of_protection", elevation=30)


def silver_amulet():
    root = setup()
    silver = steel("Silver", "#d6d8dc", 0.22)
    cyl("Disc", (0, 0, 0), 0.08, 0.015, silver, root, rot=(math.radians(90), 0, 0), verts=40)
    for i in range(12):
        a = math.tau * i / 12
        lib.box(f"Ray{i}", (0.012, 0.012, 0.05), (math.cos(a) * 0.1, 0, math.sin(a) * 0.1), mat=gold_mat(),
                parent=root, rotation=(0, -a + math.pi / 2, 0))
    sphere("Centre", (0, -0.012, 0), 0.03, gold_mat(), root, scale=(1, 0.4, 1))
    chain = [(math.cos(a) * 0.15, 0, 0.12 + math.sin(a) * 0.15)
             for a in (math.pi * (0.08 + 0.84 * i / 15) for i in range(16))]
    for i in range(len(chain) - 1):
        lib.cylinder_between(f"Chain{i}", chain[i], chain[i + 1], 0.005, mat=silver, parent=root, sides=6)
    lib.cylinder_between("Drop", (0, 0, 0.08), chain[8], 0.005, mat=silver, parent=root, sides=6)
    finish("silver_amulet", elevation=12)


def boot(name, x, mat, parent, turn=0.0):
    prof = [(0.055, 0.32), (0.06, 0.3), (0.055, 0.15), (0.05, 0.08), (0.055, 0.0)]
    shaft = lathe(name + "Shaft", prof, mat, parent, loc=(x, 0, 0))
    foot = sphere(name + "Foot", (x, -0.07, 0.04), 0.06, mat, parent, scale=(0.85, 1.9, 0.75))
    sole = lib.box(name + "Sole", (0.1, 0.24, 0.02), (x, -0.06, 0.005), mat=leather("Sole", "#2a1a10"),
                   parent=parent, bevel=0.01)
    lib.box(name + "Cuff", (0.125, 0.125, 0.04), (x, 0, 0.31), mat=leather("Cuff", "#4a3020"), parent=parent,
            bevel=0.01)
    for o in (shaft, foot, sole):
        o.rotation_euler = (0, 0, turn)


def leather_boots():
    root = setup()
    mat = leather("Boot", "#5a3a20")
    boot("L", -0.07, mat, root, 0.1)
    boot("R", 0.08, mat, root, -0.05)
    root.rotation_euler = (0, 0, math.radians(20))
    finish("leather_boots", elevation=22)


def glove(name, x, mat, parent, angle):
    g = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(g)
    g.parent = parent
    g.location = (x, 0, 0)
    g.rotation_euler = (0, 0, angle)
    lib.box(name + "Palm", (0.09, 0.1, 0.025), (0, 0, 0.015), mat=mat, parent=g, bevel=0.012)
    lib.box(name + "Cuff", (0.11, 0.08, 0.035), (0, -0.09, 0.02), mat=leather("GCuff", "#3a2414"), parent=g,
            bevel=0.012)
    for i, (fx, fl) in enumerate(((-0.033, 0.07), (-0.011, 0.085), (0.011, 0.08), (0.032, 0.065))):
        lib.cylinder_between(f"{name}F{i}", (fx, 0.05, 0.015), (fx, 0.05 + fl, 0.015), 0.011, mat=mat, parent=g,
                             sides=8)
    lib.cylinder_between(name + "Thumb", (0.045, 0.0, 0.015), (0.09, 0.05, 0.015), 0.012, mat=mat, parent=g,
                         sides=8)


def leather_gloves():
    root = setup()
    mat = leather("Glove", "#6b4528")
    glove("L", -0.07, mat, root, math.radians(20))
    glove("R", 0.08, mat, root, math.radians(-15))
    finish("leather_gloves", elevation=65)


# --------------------------------------------------------------------------
# Consumables and gear
# --------------------------------------------------------------------------

def potion(name, liquid_color):
    root = setup()
    prof = [(0.001, 0.0), (0.07, 0.005), (0.1, 0.05), (0.105, 0.1), (0.09, 0.15), (0.04, 0.19), (0.028, 0.21),
            (0.028, 0.27), (0.034, 0.28)]
    lathe("Flask", prof, glass(), root)
    inner = [(0.001, 0.008), (0.065, 0.012), (0.092, 0.05), (0.097, 0.1), (0.083, 0.13), (0.001, 0.13)]
    lathe("Liquid", inner, liquid("Liquid", liquid_color), root)
    cyl("Cork", (0, 0, 0.29), 0.026, 0.05, wood("Cork", "#a07a4a"), root, verts=16)
    lib.box("Label", (0.08, 0.005, 0.05), (0, -0.098, 0.07), mat=cloth("Label", "#e2d6b8"), parent=root)
    finish(name, elevation=20)


def potion_of_healing():
    potion("potion_of_healing", "#b81c1c")


def potion_of_greater_healing():
    potion("potion_of_greater_healing", "#7a1a6a")


def remedy():
    potion("remedy", "#4a9a3a")


def rations():
    root = setup()
    cl = cloth("Wrap", "#a89878")
    lib.box("Parcel", (0.24, 0.16, 0.08), (0.05, 0.03, 0.04), mat=cl, parent=root, bevel=0.02)
    lib.box("Twine", (0.012, 0.165, 0.085), (0.05, 0.03, 0.04), mat=cloth("Twine", "#5a4a30"), parent=root)
    bread = sphere("Bread", (-0.1, -0.06, 0.05), 0.08, wood("Crust", "#a8743a"), root, scale=(1.3, 0.9, 0.65))
    bread.name = "Bread"
    cheese = lib.mesh_object("Cheese", [(0.05, -0.12, 0), (0.17, -0.1, 0), (0.1, -0.03, 0),
                                        (0.05, -0.12, 0.06), (0.17, -0.1, 0.06), (0.1, -0.03, 0.06)],
                             [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)],
                             mat=lib.material("Cheese", lib.lin("#e0b84a"), rough=0.6, noise_var=0.2))
    cheese.parent = root
    finish("rations", elevation=45)


def apple():
    root = setup()
    sk = lib.material("Apple", lib.lin("#b02a1e"), rough=0.35, noise_var=0.35, noise_scale=6, spec=0.6)
    a = sphere("Apple", (0, 0, 0.1), 0.1, sk, root, scale=(1.05, 1.05, 0.92), seg=32)
    a.modifiers.new("Dimple", 'SIMPLE_DEFORM')
    lib.cylinder_between("Stem", (0, 0, 0.18), (0.01, 0.005, 0.23), 0.006, mat=wood("Stem", "#4a3020"), parent=root)
    leaf = lib.mesh_object("Leaf", [(0.01, 0.005, 0.21), (0.06, -0.02, 0.24), (0.1, 0.0, 0.22), (0.05, 0.02, 0.215)],
                           [(0, 1, 2, 3)], mat=cloth("Leaf", "#4a7a2a", bump=0.05), parent=root)
    leaf.name = "Leaf"
    finish("apple", elevation=30)


def torch():
    root = setup()
    grip("Stick", -0.3, 0.2, 0.02, wood("Stick", "#6a4a2a"), root)
    rag = cloth("Rag", "#3a2e22", bump=0.6)
    for i in range(4):
        grip(f"Rag{i}", 0.12 + i * 0.03, 0.2 + i * 0.03, 0.035 - i * 0.003, rag, root)
    diagonal(root)
    finish("torch", elevation=70)


def lantern():
    root = setup()
    br = brass()
    lib.box("Base", (0.14, 0.14, 0.025), (0, 0, 0.012), mat=br, parent=root, bevel=0.005)
    lib.box("Top", (0.14, 0.14, 0.025), (0, 0, 0.2), mat=br, parent=root, bevel=0.005)
    lib.mesh_object("Hood", [(-0.07, -0.07, 0.212), (0.07, -0.07, 0.212), (0.07, 0.07, 0.212), (-0.07, 0.07, 0.212),
                             (0, 0, 0.27)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], mat=br, parent=root)
    for sx in (-1, 1):
        for sy in (-1, 1):
            lib.box(f"Post{sx}{sy}", (0.015, 0.015, 0.18), (sx * 0.065, sy * 0.065, 0.11), mat=br, parent=root)
    lib.box("Glass", (0.12, 0.12, 0.17), (0, 0, 0.11), mat=glass("LGlass", "#f0e6c8"), parent=root)
    flame = lib.material("Flame", lib.lin("#ffcc66"), emission=lib.lin("#ffb040"), emission_strength=8.0)
    sphere("Flame", (0, 0, 0.09), 0.02, flame, root, scale=(1, 1, 1.8))
    torus("Handle", (0, 0, 0.31), 0.04, 0.007, br, root, rot=(math.radians(90), 0, 0))
    finish("lantern", elevation=20)


def holy_symbol():
    root = setup()
    gd = gold_mat()
    cyl("Disc", (0, 0, 0), 0.07, 0.02, gd, root, rot=(math.radians(90), 0, 0), verts=32)
    for i in range(16):
        a = math.tau * i / 16
        ln = 0.07 if i % 2 == 0 else 0.045
        lib.mesh_object(f"Ray{i}", [(math.cos(a - 0.12) * 0.07, 0, math.sin(a - 0.12) * 0.07),
                                    (math.cos(a + 0.12) * 0.07, 0, math.sin(a + 0.12) * 0.07),
                                    (math.cos(a) * (0.07 + ln), 0, math.sin(a) * (0.07 + ln))],
                        [(0, 1, 2)], mat=gd, parent=root).modifiers.new("T", 'SOLIDIFY').thickness = 0.012
    sphere("Boss", (0, -0.012, 0), 0.03, brass("Red", "#c84a2a"), root, scale=(1, 0.5, 1))
    lib.cylinder_between("Cord", (0, 0.0, 0.14), (0, 0.0, 0.26), 0.006, mat=leather("Cord", "#3b2616"), parent=root)
    finish("holy_symbol", elevation=12)


def thieves_tools():
    root = setup()
    lib.box("Roll", (0.36, 0.2, 0.012), (0, 0, 0.006), mat=leather("Roll", "#5a3a22"), parent=root, bevel=0.01)
    st = steel("Picks", "#b4b8be", 0.3)
    for i in range(6):
        x = -0.13 + i * 0.05
        lib.cylinder_between(f"Pick{i}", (x, -0.07, 0.018), (x + 0.01, 0.06, 0.018), 0.004, mat=st, parent=root,
                             sides=6)
        lib.cylinder_between(f"Handle{i}", (x, -0.09, 0.018), (x, -0.06, 0.018), 0.008,
                             mat=wood("PickWood", "#3a2818"), parent=root, sides=8)
    lib.box("Pocket", (0.36, 0.06, 0.016), (0, -0.075, 0.016), mat=leather("Pocket", "#4a3020"), parent=root)
    root.rotation_euler = (0, 0, math.radians(20))
    finish("thieves_tools", elevation=60)


def spellbook():
    root = setup()
    cover = leather("Cover", "#4a2a5a")
    lib.box("Cover", (0.24, 0.32, 0.07), (0, 0, 0.035), mat=cover, parent=root, bevel=0.012)
    lib.box("Pages", (0.225, 0.305, 0.055), (0.01, 0, 0.035), mat=cloth("Pages", "#e8dcc0"), parent=root)
    gd = gold_mat()
    for y in (-0.12, 0.12):
        lib.box(f"Corner{y}", (0.05, 0.05, 0.074), (0.1, y, 0.035), mat=gd, parent=root, bevel=0.005)
    cyl("Sigil", (0, 0, 0.072), 0.05, 0.004, gd, root, verts=24)
    lib.box("Clasp", (0.04, 0.03, 0.03), (0.125, 0, 0.035), mat=gd, parent=root, bevel=0.005)
    root.rotation_euler = (0, 0, math.radians(-25))
    finish("spellbook", elevation=50)


def garnet():
    root = setup()
    gem = lib.primitive("ico_sphere", "Gem", mat=liquid("Garnet", "#8a0f1a", glow=0.35), parent=root, radius=0.08,
                        subdivisions=2, location=(0, 0, 0.05))
    gem.scale = (1.1, 1, 0.6)
    finish("garnet", elevation=35)


def key():
    root = setup()
    ir = iron("KeyIron")
    torus("Bow", (-0.12, 0, 0), 0.045, 0.012, ir, root)
    grip("Shank", -0.075, 0.14, 0.01, ir, root)
    lib.box("Bit1", (0.02, 0.05, 0.015), (0.12, -0.03, 0), mat=ir, parent=root)
    lib.box("Bit2", (0.02, 0.035, 0.015), (0.09, -0.022, 0), mat=ir, parent=root)
    diagonal(root)
    finish("key", elevation=75)


def gold():
    root = setup()
    gd = gold_mat()
    r = np.random.default_rng(5)
    k = 0
    for layer, count in ((0, 14), (1, 8), (2, 4)):
        for i in range(count):
            ang = r.uniform(0, math.tau)
            rad = r.uniform(0, 0.11 - layer * 0.03)
            c = cyl(f"Coin{k}", (math.cos(ang) * rad, math.sin(ang) * rad, 0.006 + layer * 0.012 + r.uniform(0, 0.004)),
                    0.03, 0.006, gd, root, verts=20)
            c.rotation_euler = (r.uniform(-0.25, 0.25), r.uniform(-0.25, 0.25), 0)
            k += 1
    finish("gold", elevation=45)


ALL = {
    "longsword": longsword, "shortsword": shortsword, "dagger": dagger, "rapier": rapier, "greataxe": greataxe,
    "mace": mace,
    "quarterstaff": quarterstaff, "warhammer": warhammer, "shortbow": shortbow, "arrows": arrows,
    "leather": leather_armor, "studded_leather": studded_leather, "chain_shirt": chain_shirt,
    "chain_mail": chain_mail, "shield": shield, "iron_helm": iron_helm,
    "cloak_of_protection": cloak_of_protection, "ring_of_protection": ring_of_protection,
    "silver_amulet": silver_amulet, "leather_boots": leather_boots, "leather_gloves": leather_gloves,
    "potion_of_healing": potion_of_healing, "potion_of_greater_healing": potion_of_greater_healing,
    "remedy": remedy,
    "rations": rations, "apple": apple, "torch": torch, "lantern": lantern, "holy_symbol": holy_symbol,
    "thieves_tools": thieves_tools, "spellbook": spellbook, "garnet": garnet, "key": key, "gold": gold,
}


def run(names=None):
    for name in names or ALL:
        ALL[name]()
