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


def finish(name, root, door=None, extra_margin=(0, 0, 0, 0)):
    """Frames everything under `root`, renders, and records origin/door pixels."""
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name != "ShadowCatcher"]
    cam, res = lib.frame_oblique(objs, margin_px=8, extra=extra_margin, shadows=True)
    path = lib.ASSETS / "props" / f"{name}.png"
    lib.render(path, res=res, shadow_alpha=0.6)
    origin = lib.to_pixel(cam, root.matrix_world @ Vector((0, 0, 0)), res)
    entry = {"origin": [round(origin[0]), round(origin[1])], "size": list(res)}
    if door is not None:
        dp = lib.to_pixel(cam, root.matrix_world @ Vector(door), res)
        entry["door_pixel"] = [round(dp[0]), round(dp[1])]
    MANIFEST[name] = entry
    print("wrote", path, entry)


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
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 4.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.blend_type = 'OVERLAY'
    lib.sock(mix.inputs, "Factor_Float").default_value = 0.35
    nt.links.new(brick.outputs["Color"], lib.sock(mix.inputs, "A_Color"))
    nt.links.new(noise.outputs["Color"], lib.sock(mix.inputs, "B_Color"))
    nt.links.new(lib.sock(mix.outputs, "Result_Color"), bsdf.inputs["Base Color"])
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

def tree_oak():
    root = setup()
    r = np.random.default_rng(11)
    bark = bark_material()
    lib.cylinder_between("Trunk", (0, 0, -0.1), (0.15, 0.05, 2.6), 0.26, 0.15, mat=bark, parent=root)
    for k in range(6):
        ang = k * math.pi / 3 + r.uniform(-0.3, 0.3)
        end = (math.cos(ang) * 1.3, math.sin(ang) * 1.1, 3.4 + r.uniform(-0.2, 0.4))
        lib.cylinder_between(f"Branch{k}", (0.1, 0.05, 2.3), end, 0.11, 0.05, mat=bark, parent=root, sides=8)
    for k in range(4):
        ang = k * math.pi / 2 + 0.4
        lib.cylinder_between(f"Root{k}", (0, 0, 0.25), (math.cos(ang) * 0.55, math.sin(ang) * 0.5, -0.05),
                             0.12, 0.04, mat=bark, parent=root, sides=8)
    clusters = [((0.0, 0.0, 4.3), 1.55), ((-1.2, 0.3, 3.7), 1.2), ((1.25, -0.2, 3.8), 1.2),
                ((0.3, 1.0, 4.0), 1.15), ((-0.4, -1.0, 3.6), 1.1), ((0.7, 0.4, 5.0), 1.0),
                ((-0.8, 0.2, 4.9), 0.95), ((1.6, 0.8, 3.3), 0.8), ((-1.7, -0.6, 3.2), 0.8)]
    # Dark inner mass so gaps read as deep foliage, not holes.
    inner = lib.material("InnerLeaf", lib.lin("#1d3314"), rough=0.9)
    for i, (c, rad) in enumerate(clusters):
        lib.primitive("ico_sphere", f"Inner{i}", mat=inner, parent=root, subdivisions=2,
                      radius=rad * 0.72, location=c)
    r2 = np.random.default_rng(13)
    for k in range(10):  # small extra lumps break up the round silhouette
        c, rad = clusters[r2.integers(len(clusters))]
        d = r2.normal(size=3)
        d /= np.linalg.norm(d)
        clusters.append((tuple(np.array(c) + d * rad * 0.8), rad * r2.uniform(0.35, 0.55)))
    leaf_cloud("Leaves", clusters, 30000, 12, parent=root)
    root.scale = (0.82, lib.DEPTH_STRETCH * 0.82, 0.82)
    finish("tree_oak", root)


def tree_pine():
    root = setup()
    bark = bark_material(color="#4d3b2c")
    lib.cylinder_between("Trunk", (0, 0, -0.1), (0, 0, 7.8), 0.22, 0.04, mat=bark, parent=root)
    r = np.random.default_rng(21)
    verts, faces, cols = [], [], []
    pal = np.array([lib.lin(c) for c in ("#1f3a28", "#27442e", "#183022", "#2f4c32", "#355236")])
    tiers = 12
    for t in range(tiers):
        frac = t / tiers
        z0 = 1.2 + t * 0.55
        rad = 2.0 * (1 - frac) ** 1.05 + 0.2
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
    finish("tree_pine", root)


def bush():
    root = setup()
    clusters = [((0, 0, 0.55), 0.6), ((-0.5, 0.15, 0.42), 0.45), ((0.5, -0.1, 0.45), 0.45),
                ((0.1, 0.4, 0.5), 0.4)]
    inner = lib.material("InnerBush", lib.lin("#1d3314"), rough=0.9)
    for i, (c, rad) in enumerate(clusters):
        lib.primitive("ico_sphere", f"Inner{i}", mat=inner, parent=root, subdivisions=2, radius=rad * 0.7, location=c)
    leaf_cloud("Leaves", clusters, 4200, 31, size=(0.05, 0.09),
               palette=("#3a6428", "#4a7430", "#2f5522", "#58803a"), parent=root)
    berry = lib.material("Berry", lib.lin("#9a1d24"), rough=0.3, spec=0.6)
    r = np.random.default_rng(32)
    for k in range(18):
        c, rad = clusters[r.integers(len(clusters))]
        d = r.normal(size=3)
        d /= np.linalg.norm(d)
        p = np.array(c) + d * rad * 0.95
        if p[2] < 0.2:
            continue
        lib.primitive("uv_sphere", f"Berry{k}", mat=berry, parent=root, segments=8, ring_count=6, radius=0.035,
                      location=tuple(p))
    finish("bush", root)


def rock():
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
    for name, loc, rad, scale, seed in (("Boulder", (0, 0, 0.12), 0.62, (1.2, 0.95, 0.7), 0.0),
                                        ("Stone", (0.78, -0.3, 0.02), 0.25, (1.1, 0.9, 0.7), 3.0)):
        obj = lib.primitive("ico_sphere", name, mat=mat, parent=root, subdivisions=5, radius=rad, location=loc)
        obj.scale = scale
        big = lib.displace(obj, strength=rad * 0.45, scale=rad * 0.9, depth=2)
        big.texture.noise_basis = 'VORONOI_F2'
        lib.displace(obj, strength=rad * 0.12, scale=rad * 0.25, depth=4)
        obj.data.shade_smooth()
    finish("rock", root)


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


def cottage():
    root = setup()
    cols, rows = 8, 6
    width = cols * lib.HEX_M - 0.4
    depth = footprint_depth(rows)
    wall_top = 2.9
    plaster = plaster_material()
    timber = wood_material("Timber", "#4a3322")
    stone = stone_material("Plinth", "#7d776c", scale=3.5)
    # Body: stone plinth and plastered walls.
    lib.box("Plinth", (width, depth, 0.5), (0, depth / 2, 0.25), mat=stone, parent=root)
    lib.box("Walls", (width - 0.1, depth - 0.1, wall_top - 0.5), (0, depth / 2, 0.5 + (wall_top - 0.5) / 2),
            mat=plaster, parent=root)
    # Timber framing on the front face.
    front = -0.02
    lib.box("Sill", (width, 0.16, 0.2), (0, front, 0.55), mat=timber, parent=root, bevel=0.02)
    lib.box("TopBeam", (width, 0.16, 0.22), (0, front, wall_top - 0.11), mat=timber, parent=root, bevel=0.02)
    bays = 6
    bay_w = width / bays
    door_bay = 3
    for b in range(bays + 1):
        x = -width / 2 + b * bay_w
        lib.box(f"Post{b}", (0.2, 0.16, wall_top - 0.55), (x, front, 0.55 + (wall_top - 0.55) / 2), mat=timber,
                parent=root, bevel=0.02)
    glass = lib.material("Glass", lib.lin("#28323a"), rough=0.08, spec=0.9, emission=lib.lin("#ffb35a"),
                         emission_strength=0.15)
    shutter = wood_material("Shutter", "#4d5a3a")
    for b in range(bays):
        cx = -width / 2 + (b + 0.5) * bay_w
        if b == door_bay:
            continue
        # Diagonal braces under the window.
        for side in (-1, 1):
            a = Vector((cx + side * bay_w * 0.45, front, 0.65))
            c = Vector((cx + side * 0.25, front, 1.2))
            lib.cylinder_between(f"Brace{b}{side}", a, c, 0.07, mat=timber, parent=root, sides=4)
        window(f"Win{b}", cx, 1.75, 0.8, 0.75, root, timber, glass, shutter, timber, y=front)
    # Door with frame and stone step.
    door_x = -width / 2 + (door_bay + 0.5) * bay_w
    door = wood_material("Door", "#5a3a20")
    lib.box("DoorFrame", (1.2, 0.18, 2.15), (door_x, front - 0.01, 1.57), mat=timber, parent=root, bevel=0.02)
    lib.box("Door", (0.95, 0.12, 1.95), (door_x, front - 0.05, 1.5), mat=door, parent=root, bevel=0.01)
    iron = iron_material()
    for z in (0.95, 2.05):
        lib.box(f"Hinge{z}", (0.6, 0.02, 0.05), (door_x - 0.12, front - 0.12, z), mat=iron, parent=root)
    lib.box("Step", (1.5, 0.5, 0.18), (door_x, -0.2, 0.09), mat=stone_material("Step", "#8e897e", scale=2.0),
            parent=root, bevel=0.03)
    # Thatched roof, gable ends and ridge.
    thatch = tiled_roof_material("Thatch", "#8c7752", thatch=True)
    ridge_z = roof_slopes("Thatch", width, depth, wall_top, 47, 0.55, thatch, root, thickness=0.4)
    gable_walls("Gable", width - 0.1, depth, wall_top, ridge_z, plaster, root)
    lib.cylinder_between("Ridge", (-width / 2 - 0.5, depth / 2, ridge_z + 0.3),
                                 (width / 2 + 0.5, depth / 2, ridge_z + 0.3), 0.32,
                                 mat=tiled_roof_material("Ridge", "#7d6a40", thatch=True), parent=root, sides=14)
    # Chimney.
    chim = stone_material("Chimney", "#837c70", scale=4.0)
    lib.box("Chimney", (0.9, 0.9, 2.8), (-width / 2 + 2.0, depth * 0.65, ridge_z - 0.2), mat=chim, parent=root)
    lib.box("ChimneyCap", (1.05, 1.05, 0.14), (-width / 2 + 2.0, depth * 0.65, ridge_z + 1.25), mat=chim,
            parent=root, bevel=0.02)
    finish("house_small", root, door=(door_x, 0, 0.05))


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


ALL = {
    "tree_oak": tree_oak,
    "tree_pine": tree_pine,
    "bush": bush,
    "rock": rock,
    "sign": sign,
    "well": well,
    "bridge_wood": bridge_wood,
    "house_small": cottage,
    "house_large": inn,
}


def write_manifest():
    """Writes rendered origins / door pixels back into data/props/props.json."""
    path = lib.ROOT / "data" / "props" / "props.json"
    data = json.loads(path.read_text())
    for name, entry in MANIFEST.items():
        if name in data["props"]:
            data["props"][name]["origin"] = entry["origin"]
            if "door_pixel" in entry:
                data["props"][name]["door_pixel"] = entry["door_pixel"]
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
        ALL[name]()
    write_manifest()
