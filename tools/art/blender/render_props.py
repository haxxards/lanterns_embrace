"""Pre-rendered props and buildings.

Every prop is built around its anchor at the world origin: the trunk base for
trees, the centre of the front wall's base for buildings (the bottom-centre of
the hex footprint, matching PropDef.placement_point in the game). After
rendering, the anchor's pixel is written to data/props/props.json as "origin"
(and the door's pixel as "door_pixel"), so re-rendering keeps the data right.
"""
import json
import math

import bpy
import numpy as np
from mathutils import Vector

import lib

SAMPLES = 96
MANIFEST = {}


# --------------------------------------------------------------------------
# Scene helpers
# --------------------------------------------------------------------------

def setup():
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=(0.62, 0.70, 0.82), sky_strength=1.0)
    lib.add_sun(strength=4.0, angle_deg=10.0)
    lib.add_shadow_catcher()
    return lib.oblique_root()


def finish(name, root, door=None, extra_margin=(0, 0, 0, 0), variant=0):
    """Frames everything under `root`, renders, and records origin/door pixels.
    Variant 0 is <name>.png, variant n is <name>_<n+1>.png."""
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name != "ShadowCatcher"]
    cam, res = lib.frame_oblique(objs, margin_px=8, extra=extra_margin, shadows=True)
    file_name = name if variant == 0 else f"{name}_{variant + 1}"
    path = lib.ASSETS / "props" / f"{file_name}.png"
    lib.render(path, res=res, shadow_alpha=0.6)
    origin = lib.to_pixel(cam, root.matrix_world @ Vector((0, 0, 0)), res)
    entry = {"texture": f"res://assets/props/{file_name}.png", "origin": [round(origin[0]), round(origin[1])]}
    if door is not None:
        dp = lib.to_pixel(cam, root.matrix_world @ Vector(door), res)
        entry["door_pixel"] = [round(dp[0]), round(dp[1])]
    looks = MANIFEST.setdefault(name, [])
    while len(looks) <= variant:
        looks.append(None)
    looks[variant] = entry
    print("wrote", path, res, entry)


def footprint_depth(rows):
    """Depth in metres from the front wall line to the back wall for `rows` hex rows."""
    r = lib.HEX_M / math.sqrt(3)  # hex corner radius in metres
    return (rows - 1) * lib.ROW_M + r


def leaf_cloud(name, clusters, count, seed, size=(0.06, 0.11), palette=("#36572a", "#41632c", "#2c4a22",
                                                                          "#4f7032", "#5f7c38", "#6c8240"),
               parent=None, shell=(0.7, 1.0), droop=0.0, rough=0.55):
    """Thousands of small leaf quads scattered over spherical clusters."""
    r = np.random.default_rng(seed)
    centers = np.array([c[0] for c in clusters], dtype=float)
    radii = np.array([c[1] for c in clusters], dtype=float)
    weights = radii ** 2 / (radii ** 2).sum()
    pick = r.choice(len(clusters), size=count, p=weights)
    d = r.normal(size=(count, 3))
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    rad = radii[pick] * r.uniform(*shell, count)
    pos = centers[pick] + d * rad[:, None]
    pos[:, 2] -= droop * (pos[:, 0] ** 2 + pos[:, 1] ** 2) * 0.05
    s = r.uniform(*size, count)
    # Random leaf orientation: two tangent vectors per leaf.
    a = r.normal(size=(count, 3))
    a /= np.linalg.norm(a, axis=1, keepdims=True)
    b = np.cross(a, r.normal(size=(count, 3)))
    b /= np.linalg.norm(b, axis=1, keepdims=True)
    corners = np.array([[-1, 0], [0, -0.5], [1, 0], [0, 0.5]])
    verts = (pos[:, None, :] + (corners[None, :, 0:1] * a[:, None, :] + corners[None, :, 1:2] * b[:, None, :])
             * s[:, None, None])
    pal = np.array([lib.lin(c) for c in palette])
    col = pal[r.integers(len(pal), size=count)] * r.uniform(0.7, 1.15, (count, 1))
    # Leaves deeper inside the cluster are darker (self-shadowing helper).
    depth = (rad / radii[pick])[:, None]
    col *= 0.55 + 0.45 * depth
    faces = (np.arange(count)[:, None] * 4 + np.arange(4)[None, :])
    mat = lib.material(name + "_mat", (1, 1, 1), rough=rough, vcol=True, spec=0.3)
    return lib.mesh_object(name, verts.reshape(-1, 3), [tuple(f) for f in faces],
                           colors=np.repeat(col, 4, axis=0), mat=mat, parent=parent)


def bark_material(name="Bark", color="#4a3a2a"):
    return lib.material(name, lib.lin(color), rough=0.9, noise_var=0.35, noise_scale=6, bump=0.8, bump_scale=30)


def wood_material(name, color="#6b4a2b", grain=True):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.75
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 18.0, 1.0) if grain else (6, 6, 6)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6.0
    noise.inputs["Detail"].default_value = 8.0
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    c = lib.lin(color)
    ramp.color_ramp.elements[0].color = (*(x * 0.6 for x in c), 1)
    ramp.color_ramp.elements[1].color = (*(min(1, x * 1.3) for x in c), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def stone_material(name, color="#8a8478", scale=3.0, mortar="#4a463e", rough=0.9):
    """Rubble stone: Voronoi cells with dark mortar and bumpy faces."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    coord = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = 'DISTANCE_TO_EDGE'
    vor.inputs["Scale"].default_value = scale
    nt.links.new(coord.outputs["Object"], vor.inputs["Vector"])
    vcol = nt.nodes.new("ShaderNodeTexVoronoi")
    vcol.inputs["Scale"].default_value = scale
    nt.links.new(coord.outputs["Object"], vcol.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 25
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    edge = nt.nodes.new("ShaderNodeMapRange")
    edge.inputs["From Min"].default_value = 0.0
    edge.inputs["From Max"].default_value = 0.06
    nt.links.new(vor.outputs["Distance"], edge.inputs["Value"])
    tone = nt.nodes.new("ShaderNodeValToRGB")
    c = lib.lin(color)
    tone.color_ramp.elements[0].color = (*(x * 0.7 for x in c), 1)
    tone.color_ramp.elements[1].color = (*(min(1, x * 1.2) for x in c), 1)
    nt.links.new(vcol.outputs["Color"], tone.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    nt.links.new(edge.outputs["Result"], lib.sock(mix.inputs, "Factor_Float"))
    lib.sock(mix.inputs, "A_Color").default_value = (*lib.lin(mortar), 1)
    nt.links.new(tone.outputs["Color"], lib.sock(mix.inputs, "B_Color"))
    nt.links.new(lib.sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = 'ADD'
    nt.links.new(edge.outputs["Result"], add.inputs[0])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = 0.15
    nt.links.new(noise.outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], add.inputs[1])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.8
    bump.inputs["Distance"].default_value = 0.05
    nt.links.new(add.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def tiled_roof_material(name, color, rows_per_m=6.0, cols_per_m=4.0, thatch=False):
    """Slate/shingle rows (Brick texture) or thatch strands, in object space.
    Roof slope objects are built with local +y running down the slope."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    c = lib.lin(color)
    if thatch:
        # Thatch at game scale: horizontal courses, elongated straw clumps,
        # weathered colour and mossy patches (single straws are sub-pixel).
        bsdf.inputs["Roughness"].default_value = 0.95
        clump_map = nt.nodes.new("ShaderNodeMapping")
        clump_map.inputs["Scale"].default_value = (9.0, 1.6, 1.6)
        nt.links.new(coord.outputs["Object"], clump_map.inputs["Vector"])
        clumps = nt.nodes.new("ShaderNodeTexVoronoi")
        clumps.inputs["Scale"].default_value = 1.0
        nt.links.new(clump_map.outputs["Vector"], clumps.inputs["Vector"])
        straw_map = nt.nodes.new("ShaderNodeMapping")
        straw_map.inputs["Scale"].default_value = (45.0, 2.5, 2.5)
        nt.links.new(coord.outputs["Object"], straw_map.inputs["Vector"])
        straw = nt.nodes.new("ShaderNodeTexNoise")
        straw.inputs["Scale"].default_value = 1.0
        straw.inputs["Detail"].default_value = 6.0
        nt.links.new(straw_map.outputs["Vector"], straw.inputs["Vector"])
        courses = nt.nodes.new("ShaderNodeTexWave")
        courses.wave_type = 'BANDS'
        courses.bands_direction = 'Y'
        courses.inputs["Scale"].default_value = 1.6
        courses.inputs["Distortion"].default_value = 2.0
        courses.inputs["Detail"].default_value = 3.0
        nt.links.new(coord.outputs["Object"], courses.inputs["Vector"])
        big = nt.nodes.new("ShaderNodeTexNoise")
        big.inputs["Scale"].default_value = 0.35
        big.inputs["Detail"].default_value = 3.0
        nt.links.new(coord.outputs["Object"], big.inputs["Vector"])
        # Height: courses + clumps + straw
        h1 = nt.nodes.new("ShaderNodeMath")
        h1.operation = 'MULTIPLY_ADD'
        nt.links.new(courses.outputs["Fac"], h1.inputs[0])
        h1.inputs[1].default_value = 0.5
        nt.links.new(clumps.outputs["Distance"], h1.inputs[2])
        h2 = nt.nodes.new("ShaderNodeMath")
        h2.operation = 'MULTIPLY_ADD'
        nt.links.new(straw.outputs["Fac"], h2.inputs[0])
        h2.inputs[1].default_value = 0.4
        nt.links.new(h1.outputs[0], h2.inputs[2])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 1.0
        bump.inputs["Distance"].default_value = 0.12
        nt.links.new(h2.outputs[0], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        # Colour: straw tones by clump, darker in course shadows, moss by big noise.
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (*(x * 0.42 for x in c), 1)
        ramp.color_ramp.elements[1].color = (*(min(1, x * 1.05) for x in c), 1)
        tone = nt.nodes.new("ShaderNodeMath")
        tone.operation = 'MULTIPLY_ADD'
        nt.links.new(straw.outputs["Fac"], tone.inputs[0])
        tone.inputs[1].default_value = 0.6
        nt.links.new(clumps.outputs["Distance"], tone.inputs[2])
        nt.links.new(tone.outputs[0], ramp.inputs["Fac"])
        moss_mask = nt.nodes.new("ShaderNodeMapRange")
        moss_mask.inputs["From Min"].default_value = 0.58
        moss_mask.inputs["From Max"].default_value = 0.72
        moss_mask.inputs["To Max"].default_value = 0.75
        nt.links.new(big.outputs["Fac"], moss_mask.inputs["Value"])
        moss = nt.nodes.new("ShaderNodeMix")
        moss.data_type = 'RGBA'
        moss.blend_type = 'MULTIPLY'
        nt.links.new(moss_mask.outputs["Result"], lib.sock(moss.inputs, "Factor_Float"))
        nt.links.new(ramp.outputs["Color"], lib.sock(moss.inputs, "A_Color"))
        lib.sock(moss.inputs, "B_Color").default_value = (*lib.lin("#7a8a50"), 1)
        shade_c = nt.nodes.new("ShaderNodeMix")
        shade_c.data_type = 'RGBA'
        shade_c.blend_type = 'MULTIPLY'
        inv = nt.nodes.new("ShaderNodeMapRange")
        inv.inputs["To Min"].default_value = 0.45
        inv.inputs["To Max"].default_value = 0.0
        nt.links.new(courses.outputs["Fac"], inv.inputs["Value"])
        nt.links.new(inv.outputs["Result"], lib.sock(shade_c.inputs, "Factor_Float"))
        nt.links.new(lib.sock(moss.outputs, "Result_Color"), lib.sock(shade_c.inputs, "A_Color"))
        lib.sock(shade_c.inputs, "B_Color").default_value = (0.35, 0.3, 0.24, 1)
        nt.links.new(lib.sock(shade_c.outputs, "Result_Color"), bsdf.inputs["Base Color"])
        return mat
    bsdf.inputs["Roughness"].default_value = 0.6
    brick = nt.nodes.new("ShaderNodeTexBrick")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (cols_per_m * 0.5, rows_per_m, 1.0)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], brick.inputs["Vector"])
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.035
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 1.0
    brick.inputs["Color1"].default_value = (*(x * 0.8 for x in c), 1)
    brick.inputs["Color2"].default_value = (*(min(1, x * 1.15) for x in c), 1)
    brick.inputs["Mortar"].default_value = (*(x * 0.35 for x in c), 1)
    brick.inputs["Bias"].default_value = 0.0
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.2
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.blend_type = 'OVERLAY'
    lib.sock(mix.inputs, "Factor_Float").default_value = 0.6
    nt.links.new(brick.outputs["Color"], lib.sock(mix.inputs, "A_Color"))
    nt.links.new(noise.outputs["Color"], lib.sock(mix.inputs, "B_Color"))
    # Lichen / moss spots.
    spots = nt.nodes.new("ShaderNodeTexNoise")
    spots.inputs["Scale"].default_value = 3.5
    spots.inputs["Detail"].default_value = 8.0
    nt.links.new(coord.outputs["Object"], spots.inputs["Vector"])
    smask = nt.nodes.new("ShaderNodeMapRange")
    smask.inputs["From Min"].default_value = 0.62
    smask.inputs["From Max"].default_value = 0.75
    smask.inputs["To Max"].default_value = 0.6
    nt.links.new(spots.outputs["Fac"], smask.inputs["Value"])
    lichen = nt.nodes.new("ShaderNodeMix")
    lichen.data_type = 'RGBA'
    nt.links.new(smask.outputs["Result"], lib.sock(lichen.inputs, "Factor_Float"))
    nt.links.new(lib.sock(mix.outputs, "Result_Color"), lib.sock(lichen.inputs, "A_Color"))
    lib.sock(lichen.inputs, "B_Color").default_value = (*lib.lin("#7a7a58"), 1)
    nt.links.new(lib.sock(lichen.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.9
    bump.inputs["Distance"].default_value = 0.03
    nt.links.new(brick.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def plaster_material(name="Plaster", color="#d8cdb0"):
    return lib.material(name, lib.lin(color), rough=0.95, noise_var=0.18, noise_scale=3.0, bump=0.25, bump_scale=40)


def iron_material():
    return lib.material("Iron", lib.lin("#2e2c2a"), rough=0.5, metallic=0.8)


# --------------------------------------------------------------------------
# Vegetation and small props
# --------------------------------------------------------------------------

OAK_SHAPES = [
    # seed, canopy height, horizontal spread, vertical spread, palette tint
    (11, 4.2, 1.0, 1.0, 1.0),
    (23, 3.9, 1.3, 0.8, 1.08),
    (37, 4.6, 0.85, 1.25, 0.9),
]


def tree_oak(variant=0):
    root = setup()
    seed, zc, wide, tall, tint = OAK_SHAPES[variant]
    r = np.random.default_rng(seed)
    bark = bark_material()
    lean = (r.uniform(-0.25, 0.25), r.uniform(-0.15, 0.15))
    top = (lean[0], lean[1], zc - 1.6)
    lib.cylinder_between("Trunk", (0, 0, -0.1), top, 0.27, 0.15, mat=bark, parent=root)
    n_branch = int(r.integers(5, 8))
    for k in range(n_branch):
        ang = k * 2 * math.pi / n_branch + r.uniform(-0.3, 0.3)
        end = (top[0] + math.cos(ang) * 1.3 * wide, top[1] + math.sin(ang) * 1.1 * wide,
               zc - 0.7 + r.uniform(-0.2, 0.5) * tall)
        lib.cylinder_between(f"Branch{k}", (top[0], top[1], top[2] - 0.3), end, 0.11, 0.05, mat=bark,
                             parent=root, sides=8)
    for k in range(4):
        ang = k * math.pi / 2 + r.uniform(0, 0.8)
        lib.cylinder_between(f"Root{k}", (0, 0, 0.25), (math.cos(ang) * 0.55, math.sin(ang) * 0.5, -0.05),
                             0.12, 0.04, mat=bark, parent=root, sides=8)
    clusters = [((lean[0], lean[1], zc), 1.5)]
    for k in range(int(r.integers(8, 12))):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0.6, 1.5)
        clusters.append(((lean[0] + math.cos(a) * d * wide, lean[1] + math.sin(a) * d * wide * 0.9,
                          zc + r.uniform(-0.9, 0.9) * tall), r.uniform(0.75, 1.25)))
    inner = lib.material("InnerLeaf", lib.lin("#1d3314"), rough=0.9)
    for i, (c, rad) in enumerate(clusters):
        lib.primitive("ico_sphere", f"Inner{i}", mat=inner, parent=root, subdivisions=2,
                      radius=rad * 0.72, location=c)
    for k in range(10):  # small extra lumps break up the round silhouette
        c, rad = clusters[r.integers(len(clusters))]
        d = r.normal(size=3)
        d /= np.linalg.norm(d)
        clusters.append((tuple(np.array(c) + d * rad * 0.8), rad * r.uniform(0.35, 0.55)))
    pal = [tuple(min(1.0, x * tint) for x in lib.hexcol(c)) for c in
           ("#36572a", "#41632c", "#2c4a22", "#4f7032", "#5f7c38", "#6c8240")]
    pal_hex = ["#%02x%02x%02x" % tuple(int(v * 255) for v in c) for c in pal]
    leaf_cloud("Leaves", clusters, 30000, seed + 1, palette=pal_hex, parent=root)
    root.scale = (0.82, lib.DEPTH_STRETCH * 0.82, 0.82)
    finish("tree_oak", root, variant=variant)


PINE_SHAPES = [(21, 7.8, 12, 1.0), (47, 6.6, 10, 1.1)]


def tree_pine(variant=0):
    root = setup()
    seed, height, tiers, girth = PINE_SHAPES[variant]
    bark = bark_material(color="#4d3b2c")
    lib.cylinder_between("Trunk", (0, 0, -0.1), (0, 0, height), 0.22, 0.04, mat=bark, parent=root)
    r = np.random.default_rng(seed)
    verts, faces, cols = [], [], []
    pal = np.array([lib.lin(c) for c in ("#1f3a28", "#27442e", "#183022", "#2f4c32", "#355236")])
    for t in range(tiers):
        frac = t / tiers
        z0 = 1.2 + t * (height - 1.6) / tiers
        rad = 2.0 * girth * (1 - frac) ** 1.05 + 0.2
        n_branch = int(9 + r.integers(0, 4) - frac * 4)
        for bi in range(n_branch):
            a = 2 * math.pi * (bi + r.uniform(-0.3, 0.3)) / n_branch + t * 0.5
            blen = rad * r.uniform(0.8, 1.05)
            droop = 0.45 + 0.3 * r.random()
            d = np.array([math.cos(a), math.sin(a), 0.0])
            side = np.array([-math.sin(a), math.cos(a), 0.0])
            n_needles = int(90 * blen + 20)
            for k in range(n_needles):
                u = r.uniform(0.05, 1.0)
                p = d * blen * u + np.array([0, 0, z0 - droop * u * u * blen * 0.6]) + r.normal(0, 0.04, 3)
                spray = side * r.choice([-1, 1]) * r.uniform(0.1, 0.25) + d * r.uniform(0.0, 0.12)
                spray[2] = -r.uniform(0.03, 0.12)
                w = np.cross(spray, [0, 0, 1])
                w = w / (np.linalg.norm(w) + 1e-9) * 0.025
                base = len(verts)
                verts += [p - w, p + w, p + spray + w * 0.3, p + spray - w * 0.3]
                faces.append((base, base + 1, base + 2, base + 3))
                shade = 0.55 + 0.45 * u
                cols += [pal[r.integers(len(pal))] * r.uniform(0.8, 1.15) * shade] * 4
    mat = lib.material("Needles", (1, 1, 1), rough=0.65, vcol=True)
    lib.mesh_object("Needles", verts, faces, colors=cols, mat=mat, parent=root)
    root.scale = (0.85, lib.DEPTH_STRETCH * 0.85, 0.85)
    finish("tree_pine", root, variant=variant)


def birch_bark():
    """White bark with dark horizontal lenticels and knots."""
    mat = bpy.data.materials.new("BirchBark")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.7
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (14.0, 14.0, 2.0)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.0
    noise.inputs["Detail"].default_value = 4.0
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.62
    ramp.color_ramp.elements[0].color = (*lib.lin("#e2ddd2"), 1)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (*lib.lin("#2a2622"), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def tree_birch(variant=0):
    root = setup()
    seed = (71, 83)[variant]
    r = np.random.default_rng(seed)
    bark = birch_bark()
    stems = [(0.0, 0.0)] if variant == 0 else [(-0.25, 0.05), (0.3, -0.05)]
    clusters = []
    for si, (sx, sy) in enumerate(stems):
        lean = (sx * 2.2 + r.uniform(-0.3, 0.3), sy + r.uniform(-0.2, 0.2))
        h = r.uniform(6.2, 7.2)
        top = (lean[0], lean[1], h)
        lib.cylinder_between(f"Stem{si}", (sx, sy, -0.1), top, 0.16, 0.05, mat=bark, parent=root)
        for k in range(7):
            z = r.uniform(3.0, h - 0.4)
            t = z / h
            base = (sx + (lean[0] - sx) * t, sy + (lean[1] - sy) * t, z)
            a = r.uniform(0, 2 * math.pi)
            end = (base[0] + math.cos(a) * 1.1, base[1] + math.sin(a) * 0.9, z + r.uniform(0.3, 0.9))
            lib.cylinder_between(f"Twig{si}_{k}", base, end, 0.04, 0.015, mat=bark, parent=root, sides=6)
            clusters.append((end, r.uniform(0.55, 0.85)))
        clusters.append((top, 0.8))
    leaf_cloud("Leaves", clusters, 16000, seed + 1, size=(0.04, 0.07),
               palette=("#6f8f3a", "#82a046", "#5d7c32", "#97ae52", "#a8b85c"), parent=root, shell=(0.4, 1.0))
    root.scale = (0.85, lib.DEPTH_STRETCH * 0.85, 0.85)
    finish("tree_birch", root, variant=variant)


def bush(variant=0):
    root = setup()
    r0 = np.random.default_rng(31 + variant * 17)
    clusters = [((0, 0, 0.55), 0.6)]
    for k in range(3 + variant):
        a = r0.uniform(0, 2 * math.pi)
        clusters.append(((math.cos(a) * 0.5, math.sin(a) * 0.35, r0.uniform(0.35, 0.55)), r0.uniform(0.35, 0.5)))
    inner = lib.material("InnerBush", lib.lin("#1d3314"), rough=0.9)
    for i, (c, rad) in enumerate(clusters):
        lib.primitive("ico_sphere", f"Inner{i}", mat=inner, parent=root, subdivisions=2, radius=rad * 0.7, location=c)
    leaf_cloud("Leaves", clusters, 4200, 31, size=(0.05, 0.09),
               palette=("#3a6428", "#4a7430", "#2f5522", "#58803a"), parent=root)
    berry = lib.material("Berry", lib.lin(("#9a1d24", "#e8e4f0", "#3a2a5a")[variant]), rough=0.3, spec=0.6)
    r = np.random.default_rng(32 + variant)
    for k in range((18, 40, 24)[variant]):
        c, rad = clusters[r.integers(len(clusters))]
        d = r.normal(size=3)
        d /= np.linalg.norm(d)
        p = np.array(c) + d * rad * 0.95
        if p[2] < 0.2:
            continue
        lib.primitive("uv_sphere", f"Berry{k}", mat=berry, parent=root, segments=8, ring_count=6, radius=0.035,
                      location=tuple(p))
    finish("bush", root, variant=variant)


def rock(variant=0):
    root = setup()
    mat = bpy.data.materials.new("Rock")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 4.0
    noise.inputs["Detail"].default_value = 10.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    lichen = nt.nodes.new("ShaderNodeTexNoise")
    lichen.inputs["Scale"].default_value = 2.5
    nt.links.new(coord.outputs["Object"], lichen.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*lib.lin("#4a4640"), 1)
    ramp.color_ramp.elements[1].color = (*lib.lin("#9a958a"), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    lmask = nt.nodes.new("ShaderNodeMapRange")
    lmask.inputs["From Min"].default_value = 0.55
    lmask.inputs["From Max"].default_value = 0.7
    nt.links.new(lichen.outputs["Fac"], lmask.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    nt.links.new(lmask.outputs["Result"], lib.sock(mix.inputs, "Factor_Float"))
    nt.links.new(ramp.outputs["Color"], lib.sock(mix.inputs, "A_Color"))
    lib.sock(mix.inputs, "B_Color").default_value = (*lib.lin("#6f7a42"), 1)
    nt.links.new(lib.sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.9
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    rv = np.random.default_rng(5 + variant * 13)
    pieces = [("Boulder", (0, 0, 0.12), 0.62, (1.2, 0.95, 0.7))]
    if variant == 1:
        pieces = [("Boulder", (-0.2, 0.1, 0.1), 0.55, (1.0, 0.9, 0.8)), ("Boulder2", (0.45, -0.15, 0.05), 0.4, (1.2, 1.0, 0.6))]
    elif variant == 2:
        pieces = [("Slab", (0, 0, 0.05), 0.7, (1.4, 1.0, 0.35))]
    pieces.append(("Stone", (0.78, -0.3, 0.02), 0.22, (1.1, 0.9, 0.7)))
    from mathutils import Matrix
    for name, loc, rad, scale in pieces:
        obj = lib.primitive("ico_sphere", name, mat=mat, parent=root, subdivisions=5, radius=rad, location=loc)
        obj.data.transform(Matrix.Rotation(rv.uniform(0, 6.28), 4, 'Z') @ Matrix.Rotation(rv.uniform(0, 6.28), 4, 'X'))
        obj.scale = scale
        big = lib.displace(obj, strength=rad * 0.5, scale=rad * 0.6, depth=2)
        big.texture.noise_basis = 'VORONOI_CRACKLE'
        lib.displace(obj, strength=rad * 0.15, scale=rad * 0.2, depth=4)
        dec = obj.modifiers.new("Facets", 'DECIMATE')
        dec.ratio = 0.06
        obj.data.shade_flat()
    finish("rock", root, variant=variant)


def sign():
    root = setup()
    wood = wood_material("SignWood", "#7a5a36")
    post = wood_material("PostWood", "#5a4128")
    lib.box("Post", (0.13, 0.13, 1.9), (0, 0, 0.9), mat=post, parent=root, bevel=0.02)
    lib.box("Board", (1.2, 0.07, 0.5), (0, -0.09, 1.55), mat=wood, parent=root, bevel=0.025)
    lib.box("Cap", (0.2, 0.2, 0.06), (0, 0, 1.86), mat=post, parent=root, bevel=0.01)
    ink = lib.material("Ink", lib.lin("#2a1c10"), rough=0.9)
    r = np.random.default_rng(41)
    for row in range(3):
        x = -0.48
        z = 1.68 - row * 0.12
        while x < 0.45:
            w = r.uniform(0.03, 0.1)
            lib.box(f"Glyph{row}_{x:.2f}", (w, 0.01, 0.045), (x + w / 2, -0.13, z), mat=ink, parent=root)
            x += w + r.uniform(0.02, 0.06)
    finish("sign", root)


def well():
    root = setup()
    stone = stone_material("WellStone", "#8a8478", scale=5.0)
    r = np.random.default_rng(51)
    n = 14
    for course in range(3):
        for k in range(n):
            ang = 2 * math.pi * (k + 0.5 * course) / n
            rad = 0.85
            lib.box(f"Stone{course}_{k}", (0.38 + r.uniform(-0.03, 0.03), 0.3, 0.28),
                    (math.cos(ang) * rad, math.sin(ang) * rad, 0.15 + course * 0.29),
                    mat=stone, parent=root, rotation=(0, 0, ang + math.pi / 2), bevel=0.04)
    water = lib.material("WellWater", lib.lin("#0d1e24"), rough=0.05, spec=0.8)
    lib.primitive("cylinder", "Water", mat=water, parent=root, vertices=24, radius=0.7, depth=0.05,
                  location=(0, 0, 0.6))
    post = wood_material("WellPost", "#5a4128")
    for x in (-0.95, 0.95):
        lib.box(f"Post{x}", (0.14, 0.14, 2.3), (x, 0, 1.15), mat=post, parent=root, bevel=0.015)
    lib.cylinder_between("Axle", (-1.05, 0, 1.75), (1.05, 0, 1.75), 0.06, mat=post, parent=root)
    roof = tiled_roof_material("WellRoof", "#6b4a32", rows_per_m=8)
    for side in (-1, 1):
        lib.box(f"Roof{side}", (2.5, 0.9, 0.06), (0, side * 0.4, 2.55), mat=roof, parent=root,
                        rotation=(-side * math.radians(38), 0, 0), bevel=0.01)
    rope = lib.material("Rope", lib.lin("#b49a6a"), rough=0.9)
    lib.cylinder_between("Rope", (0.1, 0, 1.72), (0.1, 0, 1.1), 0.015, mat=rope, parent=root, sides=6)
    bucket = wood_material("Bucket", "#6b4a2b", grain=False)
    lib.primitive("cylinder", "Bucket", mat=bucket, parent=root, vertices=12, radius=0.14, depth=0.24,
                  location=(0.1, 0, 0.98))
    finish("well", root)


def bridge_wood():
    root = setup()
    cols, rows = 8, 2
    width = cols * lib.HEX_M
    depth = footprint_depth(rows)
    r = np.random.default_rng(61)
    beam = wood_material("Beam", "#4f3824")
    plank = wood_material("Plank", "#7d5a36")
    for y in (0.05, depth - 0.05):
        lib.box(f"Stringer{y:.1f}", (width + 0.3, 0.22, 0.28), (0, y, 0.08), mat=beam, parent=root, bevel=0.02)
    x = -width / 2
    k = 0
    while x < width / 2:
        w = r.uniform(0.22, 0.3)
        lib.box(f"Plank{k}", (w - 0.025, depth + 0.2, 0.07), (x + w / 2, depth / 2, 0.25 + r.uniform(-0.01, 0.01)),
                mat=plank, parent=root, rotation=(0, 0, r.uniform(-0.015, 0.015)), bevel=0.01)
        x += w
        k += 1
    for y in (-0.02, depth + 0.02):
        n = 7
        for i in range(n + 1):
            px = -width / 2 + width * i / n
            lib.box(f"Post{y:.1f}_{i}", (0.14, 0.14, 0.9), (px, y, 0.6), mat=beam, parent=root, bevel=0.015)
        lib.box(f"Rail{y:.1f}", (width + 0.1, 0.1, 0.1), (0, y, 1.02), mat=beam, parent=root, bevel=0.015)
    finish("bridge_wood", root)


# --------------------------------------------------------------------------
# Buildings
# --------------------------------------------------------------------------

def window(name, x, z, w, h, parent, frame_mat, glass_mat, shutter_mat=None, sill_mat=None, y=0.0):
    lib.box(name + "Frame", (w + 0.16, 0.12, h + 0.16), (x, y - 0.04, z), mat=frame_mat, parent=parent, bevel=0.01)
    lib.box(name + "Glass", (w, 0.1, h), (x, y - 0.06, z), mat=glass_mat, parent=parent)
    lib.box(name + "MullV", (0.05, 0.13, h), (x, y - 0.07, z), mat=frame_mat, parent=parent)
    lib.box(name + "MullH", (w, 0.13, 0.05), (x, y - 0.07, z), mat=frame_mat, parent=parent)
    if sill_mat is not None:
        lib.box(name + "Sill", (w + 0.3, 0.2, 0.08), (x, y - 0.1, z - h / 2 - 0.1), mat=sill_mat, parent=parent, bevel=0.01)
    if shutter_mat is not None:
        for side in (-1, 1):
            lib.box(f"{name}Shutter{side}", (w * 0.5, 0.05, h + 0.1), (x + side * (w * 0.75 + 0.1), y - 0.09, z),
                    mat=shutter_mat, parent=parent, bevel=0.008)


def roof_slopes(name, width, depth, wall_top, pitch_deg, overhang, mat, parent, thickness=0.28):
    """Gable roof as two slabs; ridge along x at y=depth/2."""
    pitch = math.radians(pitch_deg)
    run = depth / 2 + overhang
    ridge_z = wall_top + (depth / 2) * math.tan(pitch)
    w = width / 2 + overhang
    for label, dir_y in (("Front", -1), ("Back", 1)):
        # Build the slab in place: from the ridge line down to the eave.
        ry, rz = depth / 2, ridge_z + thickness * 0.5
        ey, ez = depth / 2 + dir_y * run, ridge_z - run * math.tan(pitch) + thickness * 0.5
        n = Vector((0, dir_y * math.sin(pitch), math.cos(pitch)))
        t = thickness
        p = [(-w, ry, rz), (w, ry, rz), (w, ey, ez), (-w, ey, ez)]
        q = [tuple(Vector(v) - n * t) for v in p]
        verts = p + q
        faces = [(0, 1, 2, 3), (7, 6, 5, 4), (3, 2, 6, 7), (0, 3, 7, 4), (1, 0, 4, 5), (2, 1, 5, 6)]
        if dir_y < 0:
            faces = [tuple(reversed(f)) for f in faces]
        lib.mesh_object(name + label, verts, faces, mat=mat, parent=parent)
    return ridge_z


def gable_walls(name, width, depth, wall_top, ridge_z, mat, parent):
    for x in (-width / 2, width / 2):
        verts = [(x, 0, wall_top), (x, depth, wall_top), (x, depth / 2, ridge_z)]
        lib.mesh_object(f"{name}{x:.1f}", verts, [(0, 1, 2)], mat=mat, parent=parent)


COTTAGE_STYLES = [
    # Thatch over plaster and timber.
    dict(roof="thatch", walls="plaster", timber="#4a3322", door_bay=3, chimney=0.16, pitch=47,
         shutters="#4d5a3a", extras=()),
    # Terracotta tiles over rubble stone, flower boxes.
    dict(roof="tile", walls="stone", timber="#3e2c1e", door_bay=2, chimney=0.8, pitch=38,
         shutters="#6a3a2a", extras=("flowers",)),
    # Weathered shingles over dark timber framing, lantern and woodpile.
    dict(roof="shingle", walls="plaster", timber="#2e2218", door_bay=4, chimney=0.25, pitch=42,
         shutters="#3a4a5a", extras=("lantern", "woodpile")),
]


def flower_box(name, x, z, w, parent, y):
    box_mat = wood_material(name + "Wood", "#5a3d22")
    lib.box(name, (w, 0.22, 0.2), (x, y - 0.14, z), mat=box_mat, parent=parent, bevel=0.01)
    leaf = lib.material(name + "Leaf", lib.lin("#3a6428"), rough=0.7)
    r = np.random.default_rng(abs(hash(name)) % 1000)
    cols = [lib.material(f"{name}Bloom{i}", lib.lin(c), rough=0.5) for i, c in
            enumerate(("#c8323a", "#e8c040", "#f0ece0", "#c060a0"))]
    for k in range(int(w * 22)):
        px = x + r.uniform(-w / 2 + 0.05, w / 2 - 0.05)
        lib.primitive("ico_sphere", f"{name}L{k}", mat=leaf, parent=parent, subdivisions=1, radius=0.06,
                      location=(px, y - 0.15 + r.uniform(-0.05, 0.05), z + 0.12 + r.uniform(0, 0.08)))
        if r.random() < 0.6:
            lib.primitive("ico_sphere", f"{name}F{k}", mat=cols[r.integers(len(cols))], parent=parent,
                          subdivisions=1, radius=0.035,
                          location=(px, y - 0.2 + r.uniform(-0.05, 0.05), z + 0.2 + r.uniform(0, 0.08)))


def cottage(variant=0):
    st = COTTAGE_STYLES[variant]
    root = setup()
    cols, rows = 8, 6
    width = cols * lib.HEX_M - 0.4
    depth = footprint_depth(rows)
    wall_top = 2.9
    plaster = plaster_material("Plaster%d" % variant, ("#d8cdb0", "#d0c4a4", "#cfc6ae")[variant])
    timber = wood_material("Timber", st["timber"])
    stone = stone_material("Plinth", "#7d776c", scale=3.5)
    front = -0.02
    if st["walls"] == "stone":
        walls = stone_material("StoneWalls", "#8a8274", scale=2.4)
        lib.box("Walls", (width, depth, wall_top), (0, depth / 2, wall_top / 2), mat=walls, parent=root)
        lib.box("TopBeam", (width, 0.16, 0.22), (0, front, wall_top - 0.11), mat=timber, parent=root, bevel=0.02)
    else:
        lib.box("Plinth", (width, depth, 0.5), (0, depth / 2, 0.25), mat=stone, parent=root)
        lib.box("Walls", (width - 0.1, depth - 0.1, wall_top - 0.5), (0, depth / 2, 0.5 + (wall_top - 0.5) / 2),
                mat=plaster, parent=root)
        lib.box("Sill", (width, 0.16, 0.2), (0, front, 0.55), mat=timber, parent=root, bevel=0.02)
        lib.box("TopBeam", (width, 0.16, 0.22), (0, front, wall_top - 0.11), mat=timber, parent=root, bevel=0.02)
    bays = 6
    bay_w = width / bays
    door_bay = st["door_bay"]
    if st["walls"] != "stone":
        for b in range(bays + 1):
            x = -width / 2 + b * bay_w
            lib.box(f"Post{b}", (0.2, 0.16, wall_top - 0.55), (x, front, 0.55 + (wall_top - 0.55) / 2), mat=timber,
                    parent=root, bevel=0.02)
    glass = lib.material("Glass", lib.lin("#28323a"), rough=0.08, spec=0.9, emission=lib.lin("#ffb35a"),
                         emission_strength=0.25 if variant else 0.15)
    shutter = wood_material("Shutter", st["shutters"])
    for b in range(bays):
        cx = -width / 2 + (b + 0.5) * bay_w
        if b == door_bay:
            continue
        if st["walls"] != "stone":
            for side in (-1, 1):
                a = Vector((cx + side * bay_w * 0.45, front, 0.65))
                c = Vector((cx + side * 0.25, front, 1.2))
                lib.cylinder_between(f"Brace{b}{side}", a, c, 0.07, mat=timber, parent=root, sides=4)
        window(f"Win{b}", cx, 1.75, 0.8, 0.75, root, timber, glass, shutter, timber, y=front)
        if "flowers" in st["extras"]:
            flower_box(f"Box{b}", cx, 1.2, 1.0, root, front)
    door_x = -width / 2 + (door_bay + 0.5) * bay_w
    door = wood_material("Door", ("#5a3a20", "#3e5a3a", "#6a3a28")[variant])
    lib.box("DoorFrame", (1.2, 0.18, 2.15), (door_x, front - 0.01, 1.57), mat=timber, parent=root, bevel=0.02)
    lib.box("Door", (0.95, 0.12, 1.95), (door_x, front - 0.05, 1.5), mat=door, parent=root, bevel=0.01)
    iron = iron_material()
    for z in (0.95, 2.05):
        lib.box(f"Hinge{z}", (0.6, 0.02, 0.05), (door_x - 0.12, front - 0.12, z), mat=iron, parent=root)
    lib.box("Step", (1.5, 0.5, 0.18), (door_x, -0.2, 0.09), mat=stone_material("Step", "#8e897e", scale=2.0),
            parent=root, bevel=0.03)
    if "lantern" in st["extras"]:
        flame = lib.material("Flame", lib.lin("#ffcc66"), emission=lib.lin("#ffb040"), emission_strength=10.0)
        lib.box("LampArm", (0.06, 0.4, 0.06), (door_x + 0.85, front - 0.2, 2.3), mat=iron, parent=root)
        lib.box("Lamp", (0.18, 0.18, 0.28), (door_x + 0.85, front - 0.4, 2.1), mat=flame, parent=root)
        lib.box("LampCap", (0.26, 0.26, 0.07), (door_x + 0.85, front - 0.4, 2.27), mat=iron, parent=root)
    if "woodpile" in st["extras"]:
        logs = bark_material("Logs", "#5a4630")
        ends = wood_material("LogEnds", "#a8875a", grain=False)
        r = np.random.default_rng(91)
        x0 = -width / 2 + 0.4
        for row in range(4):
            for k in range(7 - row):
                x = x0 + (k + row * 0.5) * 0.26
                z = 0.13 + row * 0.22
                lib.cylinder_between(f"Log{row}_{k}", (x, front - 0.1, z), (x, front - 0.75, z),
                                     0.12 + r.uniform(-0.02, 0.02), mat=logs, parent=root, sides=10)
                lib.primitive("cylinder", f"LogEnd{row}_{k}", mat=ends, parent=root, vertices=10, radius=0.11,
                              depth=0.01, location=(x, front - 0.76, z)).rotation_euler = (math.radians(90), 0, 0)
    # Roof.
    if st["roof"] == "thatch":
        roof = tiled_roof_material("Thatch", "#8c7752", thatch=True)
        ridge_z = roof_slopes("Roof", width, depth, wall_top, st["pitch"], 0.55, roof, root, thickness=0.4)
        lib.cylinder_between("Ridge", (-width / 2 - 0.5, depth / 2, ridge_z + 0.3),
                             (width / 2 + 0.5, depth / 2, ridge_z + 0.3), 0.32,
                             mat=tiled_roof_material("Ridge", "#7d6a40", thatch=True), parent=root, sides=14)
    else:
        color = "#8a4430" if st["roof"] == "tile" else "#5e554a"
        roof = tiled_roof_material("Roof", color, rows_per_m=7.0 if st["roof"] == "tile" else 7.5,
                                   cols_per_m=5.0 if st["roof"] == "tile" else 2.2)
        ridge_z = roof_slopes("Roof", width, depth, wall_top, st["pitch"], 0.45, roof, root, thickness=0.22)
        lib.cylinder_between("Ridge", (-width / 2 - 0.45, depth / 2, ridge_z + 0.18),
                             (width / 2 + 0.45, depth / 2, ridge_z + 0.18), 0.14,
                             mat=tiled_roof_material("RidgeCap", color, rows_per_m=2.0), parent=root, sides=10)
    gable_walls("Gable", width - 0.1, depth, wall_top, ridge_z, plaster, root)
    chim = stone_material("Chimney", "#837c70", scale=4.0)
    cx = -width / 2 + width * st["chimney"]
    lib.box("Chimney", (0.9, 0.9, 2.8), (cx, depth * 0.65, ridge_z - 0.2), mat=chim, parent=root)
    lib.box("ChimneyCap", (1.05, 1.05, 0.14), (cx, depth * 0.65, ridge_z + 1.25), mat=chim, parent=root, bevel=0.02)
    finish("house_small", root, door=(door_x, 0, 0.05), variant=variant)


def inn():
    root = setup()
    cols, rows = 12, 8
    width = cols * lib.HEX_M - 0.4
    depth = footprint_depth(rows)
    ground_top = 2.9
    wall_top = 5.7
    stone = stone_material("InnStone", "#8a8478", scale=2.6)
    plaster = plaster_material("InnPlaster", "#e0d6bc")
    timber = wood_material("InnTimber", "#43301f")
    lib.box("GroundFloor", (width, depth, ground_top), (0, depth / 2, ground_top / 2), mat=stone, parent=root)
    lib.box("UpperFloor", (width + 0.3, depth + 0.1, wall_top - ground_top),
            (0, depth / 2 - 0.15, ground_top + (wall_top - ground_top) / 2), mat=plaster, parent=root)
    front = -0.03
    upfront = -0.33
    lib.box("Jetty", (width + 0.4, 0.3, 0.25), (0, upfront + 0.1, ground_top + 0.05), mat=timber, parent=root,
            bevel=0.03)
    lib.box("TopBeam", (width + 0.3, 0.16, 0.25), (0, upfront, wall_top - 0.12), mat=timber, parent=root,
            bevel=0.02)
    bays = 9
    bay_w = (width + 0.3) / bays
    door_bay = 4
    for b in range(bays + 1):
        x = -(width + 0.3) / 2 + b * bay_w
        lib.box(f"UPost{b}", (0.2, 0.16, wall_top - ground_top - 0.2), (x, upfront, ground_top + (wall_top - ground_top) / 2),
                mat=timber, parent=root, bevel=0.02)
    glass = lib.material("InnGlass", lib.lin("#3a2a1a"), rough=0.1, spec=0.9, emission=lib.lin("#ffb257"),
                         emission_strength=1.6)
    shutter = wood_material("InnShutter", "#5a2e24")
    for b in range(bays):
        cx = -(width + 0.3) / 2 + (b + 0.5) * bay_w
        for side in (-1, 1):
            a = Vector((cx + side * bay_w * 0.45, upfront, ground_top + 0.2))
            c = Vector((cx + side * 0.3, upfront, ground_top + 0.9))
            lib.cylinder_between(f"UBrace{b}{side}", a, c, 0.07, mat=timber, parent=root, sides=4)
        window(f"UWin{b}", cx, ground_top + 1.55, 0.75, 0.8, root, timber, glass, None, timber, y=upfront)
        if b != door_bay:
            window(f"GWin{b}", cx, 1.45, 0.8, 0.9, root, timber, glass, shutter, stone, y=front)
    door_x = -(width + 0.3) / 2 + (door_bay + 0.5) * bay_w
    door = wood_material("InnDoor", "#4f3018")
    lib.box("DoorArch", (1.9, 0.22, 2.5), (door_x, front - 0.01, 1.25), mat=stone_material("Arch", "#9a9488", 4),
            parent=root, bevel=0.04)
    lib.box("Door", (1.5, 0.12, 2.2), (door_x, front - 0.1, 1.12), mat=door, parent=root, bevel=0.01)
    lib.box("DoorSplit", (0.05, 0.13, 2.2), (door_x, front - 0.12, 1.12), mat=timber, parent=root)
    lib.box("Step", (2.4, 0.6, 0.18), (door_x, -0.25, 0.09), mat=stone_material("InnStep", "#8e897e", 2.0),
            parent=root, bevel=0.03)
    # Hanging sign and lanterns.
    iron = iron_material()
    sx = door_x + 1.9
    lib.box("SignArm", (1.1, 0.08, 0.08), (sx - 0.1, upfront - 0.4, ground_top - 0.25), mat=iron, parent=root)
    lib.box("SignBoard", (0.9, 0.06, 0.6), (sx + 0.05, upfront - 0.55, ground_top - 0.8),
            mat=wood_material("SignPaint", "#2f4a3a"), parent=root, bevel=0.02)
    flame = lib.material("Flame", lib.lin("#ffcc66"), emission=lib.lin("#ffb040"), emission_strength=12.0)
    lib.box("SignLantern", (0.18, 0.05, 0.28), (sx + 0.05, upfront - 0.6, ground_top - 0.78), mat=flame, parent=root)
    for lx in (door_x - 1.3, door_x + 1.3):
        lib.box(f"Lamp{lx:.1f}", (0.2, 0.2, 0.32), (lx, front - 0.25, 2.3), mat=flame, parent=root)
        lib.box(f"LampCap{lx:.1f}", (0.28, 0.28, 0.08), (lx, front - 0.25, 2.5), mat=iron, parent=root)
    # Slate roof with dormers.
    slate = tiled_roof_material("Slate", "#4b5664", rows_per_m=5.5, cols_per_m=3.0)
    ridge_z = roof_slopes("Roof", width + 0.3, depth, wall_top, 42, 0.6, slate, root, thickness=0.3)
    gable_walls("Gable", width + 0.2, depth, wall_top, ridge_z, plaster, root)
    lib.cylinder_between("RidgeCap", (-width / 2 - 0.7, depth / 2, ridge_z + 0.25), (width / 2 + 0.7, depth / 2, ridge_z + 0.25),
                         0.16, mat=tiled_roof_material("RidgeSlate", "#3a434e", rows_per_m=2), parent=root, sides=10)
    for k in range(3):
        dx = -width / 2 + width * (k + 1) / 4
        dy = depth * 0.2
        dz = wall_top + (depth / 2 - dy) * math.tan(math.radians(42)) * 0.35 + 0.2
        lib.box(f"Dormer{k}", (1.3, 1.6, 1.3), (dx, dy + 0.5, dz + 0.4), mat=plaster, parent=root)
        window(f"DWin{k}", dx, dz + 0.45, 0.6, 0.6, root, timber, glass, y=dy - 0.31)
        roof_slopes(f"DRoof{k}", 1.3, 1.6, dz + 1.05, 45, 0.15, slate, root, thickness=0.12)
        for o in bpy.data.objects:
            if o.name.startswith(f"DRoof{k}"):
                o.location = (dx, dy - 0.3, 0)
    chim = stone_material("InnChimney", "#837c70", scale=4.0)
    for cx in (-width / 2 + 2.2, width / 2 - 2.6):
        lib.box(f"Chimney{cx:.1f}", (1.0, 1.0, 3.0), (cx, depth * 0.62, ridge_z - 0.1), mat=chim, parent=root)
        lib.box(f"ChimneyCap{cx:.1f}", (1.15, 1.15, 0.15), (cx, depth * 0.62, ridge_z + 1.45), mat=chim, parent=root,
                bevel=0.02)
    # A couple of barrels by the door.
    barrel = wood_material("Barrel", "#6b4a2b", grain=False)
    for i, bx in enumerate((door_x - 2.6, door_x - 3.2)):
        lib.primitive("cylinder", f"Barrel{i}", mat=barrel, parent=root, vertices=16, radius=0.33, depth=0.85,
                      location=(bx, -0.45, 0.43))
    finish("house_large", root, door=(door_x, 0, 0.05))



# --------------------------------------------------------------------------
# Set dressing
# --------------------------------------------------------------------------

def temple():
    """A stone chapel with its gable to the front, a bell tower and a rose window
    (8x8 hex footprint)."""
    root = setup()
    cols, rows = 8, 8
    width = cols * lib.HEX_M - 0.4
    depth = footprint_depth(rows)
    nave_w = width - 3.2  # leaves room for the tower on the right
    nave_x = -width / 2 + nave_w / 2
    wall_top = 4.6
    stone = stone_material("TempleStone", "#9a948a", scale=2.2)
    dark = stone_material("Plinth", "#6e685e", scale=3.0)
    lib.box("Nave", (nave_w, depth, wall_top), (nave_x, depth / 2, wall_top / 2), mat=stone, parent=root)
    lib.box("Plinth", (nave_w + 0.2, depth + 0.2, 0.5), (nave_x, depth / 2, 0.25), mat=dark, parent=root)
    # Buttresses down the side and at the front corners.
    for k in range(4):
        y = 1.2 + k * (depth - 2.0) / 3
        lib.box(f"Buttress{k}", (0.6, 0.7, 3.4), (nave_x - nave_w / 2 - 0.25, y, 1.7), mat=stone, parent=root,
                bevel=0.05)
    for x in (nave_x - nave_w / 2 + 0.3, nave_x + nave_w / 2 - 0.3):
        lib.box(f"FrontButtress{x:.1f}", (0.7, 0.6, 3.8), (x, -0.25, 1.9), mat=stone, parent=root, bevel=0.05)
    # Gable roof with the ridge running front to back.
    pitch = math.radians(52)
    rise = (nave_w / 2 + 0.4) * math.tan(pitch)
    slate = tiled_roof_material("TempleSlate", "#4e5058", rows_per_m=7.5, cols_per_m=2.5)
    for side in (-1, 1):
        half = nave_w / 2 + 0.45
        v = [(nave_x + side * half, -0.4, wall_top - 0.1), (nave_x, -0.4, wall_top - 0.1 + rise),
             (nave_x, depth + 0.4, wall_top - 0.1 + rise), (nave_x + side * half, depth + 0.4, wall_top - 0.1)]
        roof = lib.mesh_object(f"Roof{side}", v, [(0, 1, 2, 3)], mat=slate, parent=root)
        sol = roof.modifiers.new("T", 'SOLIDIFY')
        sol.thickness = 0.25
    gable = lib.mesh_object("Gable", [(nave_x - nave_w / 2, -0.01, wall_top), (nave_x + nave_w / 2, -0.01, wall_top),
                                      (nave_x, -0.01, wall_top + rise - 0.3)], [(0, 1, 2)], mat=stone, parent=root)
    gable.modifiers.new("T", 'SOLIDIFY').thickness = 0.4
    lib.box("RidgeCross", (0.12, 0.12, 1.0), (nave_x, -0.3, wall_top + rise + 0.3), mat=iron_material(), parent=root)
    lib.box("CrossArm", (0.6, 0.12, 0.12), (nave_x, -0.3, wall_top + rise + 0.5), mat=iron_material(), parent=root)
    # Arched door, steps and a rose window above.
    door = wood_material("TempleDoor", "#4a2e1a")
    lib.box("DoorArchStone", (2.2, 0.3, 3.0), (nave_x, -0.12, 1.5), mat=dark, parent=root, bevel=0.05)
    lib.box("Door", (1.6, 0.2, 2.4), (nave_x, -0.2, 1.3), mat=door, parent=root, bevel=0.02)
    arch = lib.primitive("cylinder", "DoorArch", mat=door, parent=root, radius=0.8, depth=0.2, vertices=24,
                         location=(nave_x, -0.2, 2.5))
    arch.rotation_euler = (math.radians(90), 0, 0)
    for k in range(3):
        lib.box(f"Step{k}", (3.0 - k * 0.4, 0.45, 0.18), (nave_x, -0.55 + k * 0.25, 0.09 + k * 0.18), mat=dark,
                parent=root, bevel=0.02)
    glass = lib.material("RoseGlass", lib.lin("#c84a3a"), rough=0.1, emission=lib.lin("#ffb060"), emission_strength=1.6)
    rose = lib.primitive("cylinder", "Rose", mat=glass, parent=root, radius=0.9, depth=0.2, vertices=32,
                         location=(nave_x, -0.2, wall_top + 0.9))
    rose.rotation_euler = (math.radians(90), 0, 0)
    tracery = lib.primitive("torus", "RoseRim", mat=dark, parent=root, major_radius=0.95, minor_radius=0.12,
                            location=(nave_x, -0.25, wall_top + 0.9))
    tracery.rotation_euler = (math.radians(90), 0, 0)
    for k in range(4):
        lib.box(f"RoseBar{k}", (1.8, 0.1, 0.08), (nave_x, -0.3, wall_top + 0.9), mat=dark, parent=root,
                rotation=(0, math.radians(k * 45), 0))
    lancet = lib.material("Lancet", lib.lin("#3a5a8a"), rough=0.1, emission=lib.lin("#9ac0ff"), emission_strength=0.6)
    for x in (nave_x - 2.3, nave_x + 2.3):
        lib.box(f"Lancet{x:.1f}", (0.5, 0.2, 1.8), (x, -0.08, 2.4), mat=lancet, parent=root)
    # Bell tower on the right, with an open belfry and a spire.
    tx = width / 2 - 1.5
    lib.box("Tower", (2.8, 2.8, 8.0), (tx, 1.4, 4.0), mat=stone, parent=root)
    lib.box("TowerPlinth", (3.0, 3.0, 0.6), (tx, 1.4, 0.3), mat=dark, parent=root)
    shade = lib.material("Belfry", lib.lin("#141210"), rough=1.0)
    for y in (-0.01,):
        lib.box("BelfryOpen", (1.2, 0.2, 1.6), (tx, y, 6.6), mat=shade, parent=root)
    bell = lib.material("Bell", lib.lin("#a8843e"), rough=0.3, metallic=1.0)
    lib.primitive("cone", "Bell", mat=bell, parent=root, radius1=0.45, radius2=0.2, depth=0.7,
                  location=(tx, 0.05, 6.5))
    spire = lib.primitive("cone", "Spire", mat=slate, parent=root, radius1=2.1, radius2=0.05, depth=4.2, vertices=4,
                          location=(tx, 1.4, 10.1))
    spire.rotation_euler = (0, 0, math.radians(45))
    lib.box("TowerSlit", (0.3, 0.2, 1.0), (tx, -0.01, 3.2), mat=lancet, parent=root)
    finish("temple", root, door=(nave_x, 0, 0.05))


def strips(name, items, mat_rough=0.6, parent=None):
    """Many tapered strips (blades, fronds). items: list of (points[n,3], widths[n], colors[n,3])."""
    verts, faces, cols = [], [], []
    for pts, widths, cl in items:
        pts = np.asarray(pts, dtype=float)
        n = len(pts)
        for k in range(n):
            d = pts[min(k + 1, n - 1)] - pts[max(k - 1, 0)]
            side = np.cross(d, [0.0, 0.0, 1.0])
            if np.linalg.norm(side) < 1e-6:
                side = np.array([1.0, 0, 0])
            side /= np.linalg.norm(side)
            base = len(verts)
            verts += [pts[k] - side * widths[k] / 2, pts[k] + side * widths[k] / 2]
            cols += [cl[k], cl[k]]
            if k > 0:
                faces.append((base - 2, base - 1, base + 1, base))
    mat = lib.material(name + "_mat", (1, 1, 1), rough=mat_rough, vcol=True, spec=0.3)
    return lib.mesh_object(name, verts, faces, colors=cols, mat=mat, parent=parent)


def reeds(variant=0):
    root = setup()
    r = np.random.default_rng(101 + variant)
    pal = [np.array(lib.lin(c)) for c in ("#7a9a44", "#8aa64a", "#a0ac5a", "#b8b06a", "#6a8a3a")]
    items = []
    n = 130 + variant * 25
    cattail = lib.material("Cattail", lib.lin("#5a3a20"), rough=0.8)
    for k in range(n):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0, 0.55) ** 0.7
        base = np.array([math.cos(a) * d, math.sin(a) * d * 0.8, 0.0])
        h = r.uniform(0.7, 1.5)
        lean = np.array([r.normal(0, 0.15), r.normal(0, 0.1), 0])
        pts = [base + lean * (t ** 2) * h + np.array([0, 0, t * h]) for t in np.linspace(0, 1, 6)]
        c = pal[r.integers(len(pal))] * r.uniform(0.75, 1.1)
        cl = [c * (0.55 + 0.45 * t) for t in np.linspace(0, 1, 6)]
        items.append((pts, np.linspace(0.05, 0.008, 6), cl))
        if r.random() < 0.15:
            top = pts[-2]
            lib.cylinder_between(f"Cat{k}", top - np.array([0, 0, 0.18]), top + np.array([0, 0, 0.04]),
                                 0.035, mat=cattail, parent=root, sides=8)
    strips("Reeds", items, parent=root)
    finish("reeds", root, variant=variant)


def fern(variant=0):
    root = setup()
    r = np.random.default_rng(201 + variant)
    pal = [np.array(lib.lin(c)) for c in ("#3f6a28", "#4f7a30", "#5f8a36", "#36602a")]
    items = []
    fronds = 9 + variant * 2
    for f in range(fronds):
        a = 2 * math.pi * f / fronds + r.uniform(-0.2, 0.2)
        L = r.uniform(0.55, 0.9)
        rise = r.uniform(0.35, 0.6)
        c = pal[r.integers(len(pal))] * r.uniform(0.85, 1.1)
        dirv = np.array([math.cos(a), math.sin(a) * 0.85, 0])
        side = np.array([-dirv[1], dirv[0], 0])
        spine = [dirv * L * t + np.array([0, 0, rise * math.sin(t * math.pi * 0.75) * 0.9]) for t in np.linspace(0, 1, 9)]
        items.append((spine, np.full(9, 0.015), [c * 0.7] * 9))
        for k in range(1, 9):
            t = k / 9
            leaf_len = 0.16 * (1 - t) + 0.04
            for sgn in (-1, 1):
                p0 = spine[k]
                p1 = p0 + side * sgn * leaf_len + dirv * leaf_len * 0.4 - np.array([0, 0, 0.03])
                items.append(([p0, (p0 + p1) / 2, p1], np.array([0.035, 0.03, 0.005]), [c, c * 1.05, c * 1.1]))
    strips("Fern", items, parent=root)
    finish("fern", root, variant=variant)


def flowers(variant=0):
    root = setup()
    r = np.random.default_rng(301 + variant)
    heads = [("#c8302a", "#e04a32"), ("#f0ece0", "#e8c838"), ("#7a5ab8", "#4a6ac8")][variant]
    stems = []
    green = np.array(lib.lin("#4a6a2c"))
    mats = [lib.material(f"Petal{i}", lib.lin(c), rough=0.5) for i, c in enumerate(heads)]
    for k in range(55):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0, 0.7) ** 0.8
        base = np.array([math.cos(a) * d, math.sin(a) * d * 0.8, 0])
        h = r.uniform(0.25, 0.55)
        tip = base + np.array([r.normal(0, 0.05), r.normal(0, 0.05), h])
        stems.append(([base, (base + tip) / 2, tip], np.array([0.012, 0.01, 0.006]), [green * 0.7, green, green]))
        lib.primitive("ico_sphere", f"Head{k}", mat=mats[r.integers(len(mats))], parent=root, subdivisions=1,
                      radius=r.uniform(0.035, 0.055), location=tuple(tip))
    for k in range(80):  # grass between the flowers
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(0, 0.75)
        base = np.array([math.cos(a) * d, math.sin(a) * d * 0.8, 0])
        h = r.uniform(0.15, 0.35)
        tip = base + np.array([r.normal(0, 0.08), r.normal(0, 0.08), h])
        stems.append(([base, tip], np.array([0.02, 0.003]), [green * 0.6, green * 1.2]))
    strips("Stems", stems, parent=root)
    finish("flowers", root, variant=variant)


def log(variant=0):
    root = setup()
    bark = bark_material("LogBark", "#4f4030")
    ends = wood_material("LogEnd", "#9a7a50", grain=False)
    ang = (0.0, math.radians(32))[variant]
    L, rad = (2.8, 2.2)[variant], (0.3, 0.24)[variant]
    a = Vector((-math.cos(ang) * L / 2, -math.sin(ang) * L / 2, rad * 0.85))
    b = Vector((math.cos(ang) * L / 2, math.sin(ang) * L / 2, rad * 0.8))
    lib.cylinder_between("Log", a, b, rad, rad * 0.85, mat=bark, parent=root, sides=16)
    for p, rr in ((a, rad), (b, rad * 0.85)):
        cap = lib.primitive("cylinder", "Cap", mat=ends, parent=root, vertices=16, radius=rr * 0.95, depth=0.02,
                            location=tuple(p))
        cap.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    moss = lib.material("Moss", lib.lin("#3e5a24"), rough=0.95, noise_var=0.3, noise_scale=30, bump=0.8, bump_scale=90)
    r = np.random.default_rng(401 + variant)
    for k in range(22):
        t = r.uniform(0.1, 0.9)
        ang = r.uniform(-1.0, 1.0)
        p = a + (b - a) * t + Vector((0, math.sin(ang) * rad * 0.8, math.cos(ang) * rad * 0.82))
        m = lib.primitive("ico_sphere", f"Moss{k}", mat=moss, parent=root, subdivisions=2,
                          radius=rad * r.uniform(0.12, 0.25), location=tuple(p))
        m.scale = (1.5, 1.2, 0.5)
    stub_end = a + (b - a) * 0.4 + Vector((0.1, 0.35, 0.5))
    lib.cylinder_between("Stub", a + (b - a) * 0.4 + Vector((0, 0, rad * 0.5)), stub_end, 0.08, 0.04, mat=bark,
                         parent=root, sides=8)
    finish("log", root, variant=variant)


def stump(variant=0):
    root = setup()
    bark = bark_material("StumpBark", "#4a3a2a")
    lib.cylinder_between("Stump", (0, 0, -0.05), (0, 0, 0.55), 0.42, 0.36, mat=bark, parent=root, sides=18)
    rings = bpy.data.materials.new("Rings")
    rings.use_nodes = True
    nt = rings.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = 'RINGS'
    wave.inputs["Scale"].default_value = 6.0
    wave.inputs["Distortion"].default_value = 3.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    # Weathered, greyed cut face (fresh pale wood looks too bright from above).
    ramp.color_ramp.elements[0].color = (*lib.lin("#5e4c38"), 1)
    ramp.color_ramp.elements[1].color = (*lib.lin("#8a7658"), 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    lib.primitive("cylinder", "Top", mat=rings, parent=root, vertices=18, radius=0.355, depth=0.02, location=(0, 0, 0.555))
    for k in range(5):
        a = k * 2 * math.pi / 5 + 0.3
        lib.cylinder_between(f"Root{k}", (0, 0, 0.3), (math.cos(a) * 0.7, math.sin(a) * 0.6, -0.05), 0.16, 0.05,
                             mat=bark, parent=root, sides=8)
    if variant == 1:
        axe_h = wood_material("AxeHandle", "#7a5a36")
        lib.cylinder_between("Axe", (0.05, 0, 0.56), (0.45, -0.25, 1.2), 0.025, mat=axe_h, parent=root, sides=8)
        lib.box("AxeHead", (0.2, 0.04, 0.12), (0.05, 0.0, 0.6), mat=iron_material(), parent=root)
    finish("stump", root, variant=variant)


def barrel_mesh(name, loc, mat, hoop, parent, h=0.9, r=0.33, lying=False):
    from render_characters import loft
    secs = [(t * h, r * (0.86 + 0.14 * math.sin(math.pi * t)), r * (0.86 + 0.14 * math.sin(math.pi * t)), 0, 0)
            for t in np.linspace(0, 1, 9)]
    b = loft(name, secs, mat, parent, sides=20)
    for t in (0.12, 0.88):
        rr = r * (0.86 + 0.14 * math.sin(math.pi * t)) + 0.008
        hoop_o = lib.primitive("torus", name + f"Hoop{t}", mat=hoop, parent=parent, major_radius=rr, minor_radius=0.018,
                               location=(0, 0, t * h))
        hoop_o.parent = b
        hoop_o.location = (0, 0, t * h)
    b.location = loc
    if lying:
        b.rotation_euler = (math.radians(90), 0, math.radians(25))
        b.location = (loc[0], loc[1] + h / 2, loc[2] + r)
    return b


def barrels(variant=0):
    root = setup()
    wood = wood_material("Staves", "#6b4a2b")
    hoop = iron_material()
    if variant == 0:
        for i, (x, y) in enumerate(((-0.38, 0.1), (0.38, 0.12), (0.0, -0.3))):
            barrel_mesh(f"Barrel{i}", (x, y, 0), wood, hoop, root)
    else:
        barrel_mesh("Barrel0", (-0.3, 0.1, 0), wood, hoop, root)
        barrel_mesh("Barrel1", (0.35, -0.2, 0), wood, hoop, root, lying=True)
    finish("barrels", root, variant=variant)


def crates(variant=0):
    root = setup()
    wood = wood_material("CrateWood", "#8a6a42")
    dark = wood_material("CrateFrame", "#5a4128")
    r = np.random.default_rng(601 + variant)
    stacks = [((-0.35, 0.1, 0), 0.6), ((0.35, 0.05, 0), 0.6), ((-0.05, 0.1, 0.6), 0.55)] if variant == 0 else \
             [((0, 0.1, 0), 0.7), ((0.55, -0.25, 0), 0.45), ((0.05, 0.12, 0.7), 0.5)]
    for i, (p, s) in enumerate(stacks):
        rot = r.uniform(-0.2, 0.2)
        c = lib.box(f"Crate{i}", (s, s, s), (p[0], p[1], p[2] + s / 2), mat=wood, parent=root,
                    rotation=(0, 0, rot), bevel=0.015)
        for dz in (-s / 2 + 0.04, s / 2 - 0.04):
            band = lib.box(f"Band{i}{dz}", (s + 0.02, s + 0.02, 0.06), (0, 0, dz), mat=dark, parent=c, bevel=0.005)
            band.parent = c
    finish("crates", root, variant=variant)


def hay(variant=0):
    root = setup()
    straw = tiled_roof_material("Hay", "#b09a5a", thatch=True)
    twine = lib.material("Twine", lib.lin("#6a5030"), rough=0.9)
    bales = [((0, 0, 0), 0)] if variant == 0 else [((-0.45, 0, 0), 0.1), ((0.45, 0.05, 0), -0.08), ((0, 0.02, 0.5), 0.05)]
    for i, (p, rot) in enumerate(bales):
        lib.box(f"Bale{i}", (0.9, 0.5, 0.48), (p[0], p[1], p[2] + 0.24), mat=straw, parent=root,
                rotation=(0, 0, rot), bevel=0.06, segments=3)
        for dx in (-0.25, 0.25):
            lib.box(f"Twine{i}{dx}", (0.03, 0.52, 0.5), (p[0] + dx, p[1], p[2] + 0.24), mat=twine, parent=root,
                    rotation=(0, 0, rot))
    finish("hay", root, variant=variant)


def lamp_post():
    root = setup()
    stone = stone_material("LampBase", "#8a8478", scale=5)
    lib.box("Base", (0.4, 0.4, 0.3), (0, 0, 0.15), mat=stone, parent=root, bevel=0.03)
    iron = iron_material()
    lib.cylinder_between("Pole", (0, 0, 0.3), (0, 0, 2.6), 0.05, 0.04, mat=iron, parent=root, sides=10)
    lib.cylinder_between("Arm", (0, 0, 2.5), (0.35, 0, 2.55), 0.025, mat=iron, parent=root, sides=8)
    flame = lib.material("LampFlame", lib.lin("#ffd070"), emission=lib.lin("#ffb040"), emission_strength=14.0)
    lib.box("Lantern", (0.22, 0.22, 0.32), (0.35, 0, 2.3), mat=flame, parent=root)
    lib.box("LanternCap", (0.3, 0.3, 0.08), (0.35, 0, 2.49), mat=iron, parent=root, bevel=0.01)
    for dx in (-0.11, 0.11):
        for dy in (-0.11, 0.11):
            lib.box(f"Bar{dx}{dy}", (0.02, 0.02, 0.34), (0.35 + dx, dy, 2.3), mat=iron, parent=root)
    finish("lamp_post", root)


def awning_material(name, a, b):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    coord = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = 'X'
    wave.inputs["Scale"].default_value = 1.6
    wave.inputs["Distortion"].default_value = 0.0
    nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    ramp.color_ramp.elements[0].color = (*lib.lin(a), 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (*lib.lin(b), 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def market_stall(variant=0):
    root = setup()
    cols, rows = 3, 2
    width = cols * lib.HEX_M - 0.3
    depth = footprint_depth(rows)
    post = wood_material("StallPost", "#5a4128")
    for x in (-width / 2 + 0.1, width / 2 - 0.1):
        for y in (0.95, depth - 0.15):
            h = 2.35 if y < 1.5 else 2.85
            lib.box(f"Post{x:.1f}{y:.1f}", (0.1, 0.1, h), (x, y, h / 2), mat=post, parent=root)
    counter = wood_material("Counter", "#7a5a36")
    lib.box("Counter", (width - 0.2, 0.7, 0.9), (0, 0.5, 0.45), mat=counter, parent=root, bevel=0.02)
    cloth = awning_material("Awning", *(("#8a3a2e", "#d8ccb0"), ("#3a5070", "#d8ccb0"))[variant])
    from mathutils import Vector as V
    p = [V((-width / 2 - 0.2, 0.95, 2.35)), V((width / 2 + 0.2, 0.95, 2.35)),
         V((width / 2 + 0.2, depth + 0.15, 2.85)), V((-width / 2 - 0.2, depth + 0.15, 2.85))]
    lib.mesh_object("Awning", p, [(0, 1, 2, 3)], mat=cloth, parent=root)
    # Scalloped valance along the front edge.
    n_sc = 14
    verts, faces = [], []
    for k in range(n_sc):
        x0 = -width / 2 - 0.2 + (width + 0.4) * k / n_sc
        x1 = -width / 2 - 0.2 + (width + 0.4) * (k + 1) / n_sc
        base = len(verts)
        verts += [(x0, 0.94, 2.35), (x1, 0.94, 2.35), (x1, 0.94, 2.17), ((x0 + x1) / 2, 0.94, 2.08), (x0, 0.94, 2.17)]
        faces.append(tuple(range(base, base + 5)))
    lib.mesh_object("Valance", verts, faces, mat=cloth, parent=root)
    r = np.random.default_rng(701 + variant)
    if variant == 0:
        goods = [lib.material(f"Fruit{i}", lib.lin(c), rough=0.4) for i, c in
                 enumerate(("#c8302a", "#e8a030", "#8ab040", "#a03060"))]
        basket = wood_material("Basket", "#a8875a", grain=False)
        for k in range(5):
            x = -width / 2 + 0.5 + k * (width - 1.0) / 4
            lib.primitive("cylinder", f"Basket{k}", mat=basket, parent=root, vertices=14, radius=0.22, depth=0.14,
                          location=(x, 0.45, 0.97))
            m = goods[k % len(goods)]
            for j in range(9):
                lib.primitive("uv_sphere", f"Fruit{k}_{j}", mat=m, parent=root, segments=10, ring_count=6,
                              radius=0.06, location=(x + r.uniform(-0.12, 0.12), 0.45 + r.uniform(-0.12, 0.12),
                                                     1.05 + r.uniform(0, 0.06)))
    else:
        clay = [lib.material(f"Clay{i}", lib.lin(c), rough=0.6) for i, c in enumerate(("#a8603a", "#8a5030", "#c08050"))]
        for k in range(8):
            x = -width / 2 + 0.4 + k * (width - 0.8) / 7
            pot = lib.primitive("uv_sphere", f"Pot{k}", mat=clay[k % 3], parent=root, segments=14, ring_count=8,
                                radius=r.uniform(0.12, 0.18), location=(x, 0.45, 1.05))
            pot.scale = (1, 1, 1.25)
    crate = wood_material("StallCrate", "#8a6a42")
    for k, x in enumerate((-width / 2 - 0.1, width / 2 + 0.15)):
        lib.box(f"SideCrate{k}", (0.5, 0.5, 0.5), (x, 0.2, 0.25), mat=crate, parent=root, bevel=0.015)
    finish("market_stall", root, variant=variant)


def cart():
    root = setup()
    wood = wood_material("CartWood", "#6b4a2b")
    width = 2 * lib.HEX_M - 0.2
    lib.box("Bed", (width - 0.6, 1.2, 0.08), (0.1, 0.7, 0.75), mat=wood, parent=root, bevel=0.01)
    for y in (0.12, 1.28):
        lib.box(f"Side{y}", (width - 0.6, 0.06, 0.4), (0.1, y, 0.98), mat=wood, parent=root, bevel=0.01)
    lib.box("Back", (0.06, 1.2, 0.4), (width / 2 - 0.2, 0.7, 0.98), mat=wood, parent=root)
    for y in (0.3, 1.1):
        lib.cylinder_between(f"Shaft{y}", (-width / 2 + 0.3, y, 0.78), (-width / 2 - 0.9, y, 0.45), 0.04,
                             mat=wood, parent=root, sides=8)
    iron = iron_material()
    for y in (-0.02, 1.42):
        wheel = lib.primitive("torus", f"Wheel{y}", mat=wood, parent=root, major_radius=0.5, minor_radius=0.05,
                              location=(0.2, y, 0.52))
        wheel.rotation_euler = (math.radians(90), 0, 0)
        rim = lib.primitive("torus", f"Rim{y}", mat=iron, parent=root, major_radius=0.54, minor_radius=0.02,
                            location=(0.2, y, 0.52))
        rim.rotation_euler = (math.radians(90), 0, 0)
        for k in range(8):
            a = k * math.pi / 4
            lib.cylinder_between(f"Spoke{y}{k}", (0.2, y, 0.52), (0.2 + math.cos(a) * 0.48, y, 0.52 + math.sin(a) * 0.48),
                                 0.02, mat=wood, parent=root, sides=6)
    sack = lib.material("Sack", lib.lin("#b0a078"), rough=0.95, noise_var=0.2, bump=0.4, bump_scale=60)
    for k, (x, y) in enumerate(((-0.2, 0.5), (0.35, 0.8), (0.05, 0.95))):
        s = lib.primitive("uv_sphere", f"Sack{k}", mat=sack, parent=root, segments=16, ring_count=10, radius=0.3,
                          location=(x, y, 1.0))
        s.scale = (1.2, 0.9, 0.75)
        s.data.shade_smooth()
    finish("cart", root)



# --------------------------------------------------------------------------
# The wilds: a bandit camp and the ruined temple (Phase 4)
# --------------------------------------------------------------------------

def campfire():
    root = setup()
    stone = stone_material("FireStone", "#7d776c", scale=6.0)
    r = np.random.default_rng(61)
    for k in range(9):
        a = k * 2 * math.pi / 9
        s = lib.primitive("ico_sphere", f"RingStone{k}", mat=stone, parent=root, subdivisions=2,
                          radius=0.13 + r.uniform(-0.02, 0.03), location=(math.cos(a) * 0.5, math.sin(a) * 0.5, 0.06))
        s.scale = (1.2, 1.0, 0.7)
    ash = lib.material("Ash", lib.lin("#2a2420"), rough=1.0)
    lib.primitive("cylinder", "Ash", mat=ash, parent=root, vertices=20, radius=0.42, depth=0.03, location=(0, 0, 0.015))
    logs = bark_material("FireLogs", "#4a3626")
    for k in range(4):
        a = k * math.pi / 4 + 0.3
        lib.cylinder_between(f"Log{k}", (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.05),
                             (-math.cos(a) * 0.1, -math.sin(a) * 0.1, 0.32), 0.055, mat=logs, parent=root, sides=8)
    ember = lib.material("Embers", lib.lin("#ff5a1a"), emission=lib.lin("#ff4a10"), emission_strength=8.0)
    lib.primitive("ico_sphere", "Embers", mat=ember, parent=root, subdivisions=2, radius=0.2, location=(0, 0, 0.06)).scale = (1.4, 1.4, 0.4)
    flame = lib.material("CampFlame", lib.lin("#ffc860"), emission=lib.lin("#ffa030"), emission_strength=14.0)
    for k, (dx, dy, h) in enumerate(((0, 0, 0.55), (0.1, 0.06, 0.4), (-0.09, 0.04, 0.38), (0.02, -0.08, 0.32))):
        lib.primitive("cone", f"Flame{k}", mat=flame, parent=root, vertices=10, radius1=0.12, radius2=0.0, depth=h,
                      location=(dx, dy, 0.1 + h / 2))
    finish("campfire", root)


def tent():
    root = setup()
    canvas = lib.material("Canvas", lib.lin("#a8987a"), rough=0.95, noise_var=0.2, bump=0.3, bump_scale=40)
    dark = lib.material("TentDark", lib.lin("#1a1612"), rough=1.0)
    pole = wood_material("TentPole", "#5a4128")
    width = 2 * lib.HEX_M - 0.4
    depth = footprint_depth(2) - 0.2
    h = 1.6
    yc = depth / 2 + 0.1
    half = width / 2
    slope = math.atan2(h, half)
    side_len = math.hypot(h, half)
    for s in (-1, 1):
        lib.box(f"Side{s}", (side_len, depth, 0.03), (s * half / 2, yc, h / 2), mat=canvas, parent=root,
                rotation=(0, s * slope, 0))
    # Front gable with an open flap, and the back gable.
    for y, name in ((yc - depth / 2, "Front"), (yc + depth / 2, "Back")):
        v = [(-half, y, 0), (half, y, 0), (0, y, h)]
        lib.mesh_object(name, v, [(0, 1, 2)], mat=canvas, parent=root)
    lib.mesh_object("Opening", [(-0.35, yc - depth / 2 - 0.01, 0), (0.35, yc - depth / 2 - 0.01, 0),
                                (0, yc - depth / 2 - 0.01, 1.1)], [(0, 1, 2)], mat=dark, parent=root)
    lib.mesh_object("Flap", [(0.0, yc - depth / 2 - 0.02, 1.15), (0.55, yc - depth / 2 - 0.25, 0.05),
                             (0.05, yc - depth / 2 - 0.05, 0.05)], [(0, 1, 2)], mat=canvas, parent=root)
    lib.cylinder_between("Ridge", (0, yc - depth / 2 - 0.15, h + 0.03), (0, yc + depth / 2 + 0.15, h + 0.03), 0.04,
                         mat=pole, parent=root, sides=8)
    rope = lib.material("Rope", lib.lin("#c8b890"), rough=0.9)
    for y in (yc - depth / 2 - 0.15, yc + depth / 2 + 0.15):
        for s in (-1, 1):
            lib.cylinder_between(f"Guy{y}{s}", (0, y, h), (s * (half + 0.4), y, 0.02), 0.01, mat=rope, parent=root, sides=4)
    finish("tent", root)


def waymarker():
    root = setup()
    post = wood_material("WayPost", "#5a4128")
    board = wood_material("WayBoard", "#8a6a40")
    lib.box("Post", (0.14, 0.14, 1.8), (0, 0, 0.88), mat=post, parent=root, bevel=0.02)
    # An arrow-shaped board pointing along the road.
    v = [(-0.55, 0, -0.14), (0.35, 0, -0.14), (0.6, 0, 0), (0.35, 0, 0.14), (-0.55, 0, 0.14)]
    pts = [(x, -0.09 + dy, 1.5 + z) for (x, _, z) in v for dy in (0.0,)]
    obj = lib.mesh_object("Arrow", pts, [(0, 1, 2, 3, 4)], mat=board, parent=root)
    sol = obj.modifiers.new("Thick", 'SOLIDIFY')
    sol.thickness = 0.06
    paint = lib.material("WayPaint", lib.lin("#e6d6a0"), rough=0.8)
    lib.box("Stripe", (0.6, 0.01, 0.05), (-0.05, -0.13, 1.5), mat=paint, parent=root)
    stone = stone_material("Cairn", "#8a8478", scale=5.0)
    for k, (x, y, rad) in enumerate(((0.2, 0.15, 0.16), (-0.2, 0.1, 0.13), (0.05, -0.18, 0.12), (0.0, 0.05, 0.1))):
        lib.primitive("ico_sphere", f"Cairn{k}", mat=stone, parent=root, subdivisions=2, radius=rad,
                      location=(x, y, rad * 0.6))
    finish("waymarker", root)


def ruin_stone():
    return stone_material("RuinStone", "#9a948a", scale=2.2, mortar="#5a564e")


def ruined_wall(variant=0):
    root = setup()
    stone = ruin_stone()
    moss = lib.material("Moss", lib.lin("#3c4e26"), rough=0.95, noise_var=0.35)
    width = 3 * lib.HEX_M - 0.25
    y = 0.45
    r = np.random.default_rng(71 + variant)
    n = 9
    for k in range(n):
        x0 = -width / 2 + k * width / n
        # A jagged, crumbling top: tall in the middle (variant 0) or with a gap (variant 1).
        f = k / (n - 1)
        top = 2.4 - 1.6 * abs(f - 0.5) * 2 + r.uniform(-0.35, 0.25)
        if variant == 1:
            top = (2.6 if k in (0, 1, n - 2, n - 1) else 0.6 + r.uniform(0, 0.4)) + r.uniform(-0.3, 0.2)
        top = max(0.35, top)
        lib.box(f"Course{k}", (width / n + 0.02, 0.55, top), (x0 + width / n / 2, y, top / 2), mat=stone, parent=root,
                bevel=0.03)
        if r.random() < 0.35:
            lib.box(f"Moss{k}", (width / n * 0.6, 0.4, 0.03), (x0 + width / n / 2, y, top + 0.01), mat=moss, parent=root)
    if variant == 0:  # a broken window arch
        dark = lib.material("RuinShadow", lib.lin("#2a2622"), rough=1.0)
        lib.box("Window", (0.5, 0.58, 0.8), (0.0, y, 1.35), mat=dark, parent=root)
    for k in range(5):  # fallen blocks at its foot
        b = lib.box(f"Fallen{k}", (0.35, 0.3, 0.25), (r.uniform(-width / 2, width / 2), y - 0.45 + r.uniform(-0.1, 0.1), 0.12),
                    mat=stone, parent=root, rotation=(0, 0, r.uniform(0, 3)), bevel=0.03)
        _ = b
    finish("ruined_wall", root, variant=variant)


def broken_column(variant=0):
    root = setup()
    stone = ruin_stone()
    h = 2.6 if variant == 0 else 0.9
    lib.box("Plinth", (0.8, 0.8, 0.25), (0, 0, 0.125), mat=stone, parent=root, bevel=0.03)
    col = lib.primitive("cylinder", "Shaft", mat=stone, parent=root, vertices=16, radius=0.28, depth=h,
                        location=(0, 0, 0.25 + h / 2))
    for k in range(8):  # fluting
        a = k * math.pi / 4
        lib.box(f"Flute{k}", (0.04, 0.04, h), (math.cos(a) * 0.28, math.sin(a) * 0.28, 0.25 + h / 2), mat=stone,
                parent=root, rotation=(0, 0, a))
    # A broken, slanted top.
    lib.box("Break", (0.62, 0.62, 0.2), (0, 0, 0.25 + h), mat=stone, parent=root, rotation=(math.radians(14), math.radians(-9), 0))
    if variant == 1:  # the fallen drums beside it
        for k, (x, y) in enumerate(((0.75, -0.25), (0.95, 0.35))):
            d = lib.primitive("cylinder", f"Drum{k}", mat=stone, parent=root, vertices=16, radius=0.27, depth=0.5,
                              location=(x, y, 0.27))
            d.rotation_euler = (math.radians(90), 0, math.radians(30 + k * 40))
    _ = col
    finish("broken_column", root, variant=variant)


def rubble():
    root = setup()
    stone = ruin_stone()
    r = np.random.default_rng(83)
    for k in range(9):
        lib.box(f"Block{k}", (r.uniform(0.18, 0.4), r.uniform(0.15, 0.3), r.uniform(0.1, 0.22)),
                (r.uniform(-0.55, 0.55), r.uniform(-0.45, 0.45), 0.08), mat=stone, parent=root,
                rotation=(r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), r.uniform(0, 3)), bevel=0.02)
    finish("rubble", root)


def standing_stone():
    root = setup()
    stone = stone_material("Menhir", "#8e8a80", scale=1.6, mortar="#6a665e")
    s = lib.box("Menhir", (0.6, 0.35, 2.0), (0, 0, 1.0), mat=stone, parent=root, bevel=0.12, segments=3)
    s.rotation_euler = (0, math.radians(3), 0)
    rune = lib.material("Runes", lib.lin("#9ad8ff"), emission=lib.lin("#7ac8ff"), emission_strength=3.0)
    for k, (x, z, w, hgt) in enumerate(((-0.1, 1.55, 0.05, 0.25), (0.08, 1.5, 0.18, 0.04), (0.0, 1.2, 0.04, 0.3),
                                         (-0.12, 1.0, 0.16, 0.04), (0.1, 0.85, 0.04, 0.22))):
        lib.box(f"Rune{k}", (w, 0.02, hgt), (x, -0.185, z), mat=rune, parent=root)
    moss = lib.material("StoneMoss", lib.lin("#56703a"), rough=0.95)
    lib.box("Moss", (0.62, 0.37, 0.12), (0, 0, 0.06), mat=moss, parent=root)
    finish("standing_stone", root)


def variants(fn, n):
    return [lambda i=i: fn(i) for i in range(n)]


ALL = {
    "tree_oak": variants(tree_oak, len(OAK_SHAPES)),
    "tree_pine": variants(tree_pine, len(PINE_SHAPES)),
    "tree_birch": variants(tree_birch, 2),
    "bush": variants(bush, 3),
    "rock": variants(rock, 3),
    "sign": [sign],
    "well": [well],
    "bridge_wood": [bridge_wood],
    "house_small": variants(cottage, len(COTTAGE_STYLES)),
    "house_large": [inn],
    "reeds": variants(reeds, 3),
    "fern": variants(fern, 3),
    "flowers": variants(flowers, 3),
    "log": variants(log, 2),
    "stump": variants(stump, 2),
    "barrels": variants(barrels, 2),
    "crates": variants(crates, 2),
    "hay": variants(hay, 2),
    "lamp_post": [lamp_post],
    "market_stall": variants(market_stall, 2),
    "cart": [cart],
    "temple": [temple],
    "campfire": [campfire],
    "tent": [tent],
    "waymarker": [waymarker],
    "ruined_wall": variants(ruined_wall, 2),
    "broken_column": variants(broken_column, 2),
    "rubble": [rubble],
    "standing_stone": [standing_stone],
}


def write_manifest():
    """Writes rendered looks (texture, origin, door pixel) into data/props/props.json.
    One look is stored at the top level; several go in a "variants" list."""
    path = lib.ROOT / "data" / "props" / "props.json"
    data = json.loads(path.read_text())
    for name, looks in MANIFEST.items():
        if name not in data["props"] or any(look is None for look in looks):
            continue
        entry = data["props"][name]
        for key in ("texture", "origin", "door_pixel", "variants"):
            entry.pop(key, None)
        if len(looks) == 1:
            new = dict(looks[0])
        else:
            new = {"variants": looks}
        # Keep "name" first, then the looks, then the remaining fields.
        ordered = {"name": entry.pop("name", name)}
        ordered.update(new)
        ordered.update(entry)
        data["props"][name] = ordered
    out = ['{', '\t"schema_version": %d,' % data.get("schema_version", 1), '\t"props": {']
    items = list(data["props"].items())
    for i, (k, v) in enumerate(items):
        lines = [f'\t\t"{k}": {{']
        kv = list(v.items())
        for j, (kk, vv) in enumerate(kv):
            lines.append(f'\t\t\t"{kk}": {json.dumps(vv)}' + (',' if j < len(kv) - 1 else ''))
        lines.append('\t\t}' + (',' if i < len(items) - 1 else ''))
        out += lines
    out += ['\t}', '}']
    path.write_text('\n'.join(out) + '\n')
    print("updated", path)


def run(names=None):
    for name in names or ALL:
        for fn in ALL[name]:
            fn()
    write_manifest()
