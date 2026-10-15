"""Building interiors: room backdrops and furniture.

An interior map is exactly as big as the building's footprint outside (a
cottage is 8x6 hexes, the inn 12x8). Each room is pre-rendered as one
"backdrop" image: floor, back wall with hearth and windows, side walls leaning
out (the classic cutaway look, so they are visible from the game's camera)
and a low front sill with a gap at the door. Furniture is rendered separately
as props, so characters sort in front of and behind it correctly.

Backdrops are written to assets/interiors/<name>.png plus
assets/interiors/backdrops.json (the pixel at hex [0, 0] and where the exit
is), which tools/maps/generate_interiors.py reads to build the interior maps.
Furniture looks are written into data/props/props.json like any other prop.
"""
import json
import math

import bpy
import numpy as np
from mathutils import Vector

import lib
import render_props as rp

SAMPLES = 96
# Interiors: a soft warm key from the same direction as outdoors (upper left),
# a dim warm ambient, plus local lights (hearth, windows) in the rooms.
KEY_STRENGTH = 3.4
KEY_COLOR = (1.0, 0.88, 0.72)
AMBIENT = (0.5, 0.44, 0.38)
BACKDROPS = {}


# --------------------------------------------------------------------------
# Scenes
# --------------------------------------------------------------------------

def furniture_setup():
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=AMBIENT, sky_strength=0.9)
    lib.add_sun(strength=KEY_STRENGTH, angle_deg=14.0, color=KEY_COLOR)
    lib.add_shadow_catcher()
    return lib.oblique_root()


def room_setup():
    lib.reset_scene(samples=SAMPLES, transparent=True, sky=AMBIENT, sky_strength=0.6)
    lib.add_sun(strength=KEY_STRENGTH * 0.75, angle_deg=14.0, color=KEY_COLOR)
    return lib.oblique_root()


def point_light(name, loc, energy, color, radius=0.2, parent=None):
    data = bpy.data.lights.new(name, 'POINT')
    data.energy = energy
    data.color = color
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data)
    lib.link(obj, parent)
    obj.location = loc
    return obj


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

def plank_floor(name, color="#7a5636", plank_w=0.2, plank_l=1.9, dark=0.7):
    """Floorboards: a Brick texture shaped into long planks, with grain noise."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.7
    coord = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.37
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Brick Width"].default_value = plank_l
    brick.inputs["Row Height"].default_value = plank_w
    brick.inputs["Mortar Size"].default_value = 0.006
    brick.inputs["Bias"].default_value = 0.0
    c = lib.lin(color)
    brick.inputs["Color1"].default_value = (*c, 1)
    brick.inputs["Color2"].default_value = (*(x * dark for x in c), 1)
    brick.inputs["Mortar"].default_value = (0.02, 0.015, 0.01, 1)
    nt.links.new(coord.outputs["Object"], brick.inputs["Vector"])
    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 3.0
    grain.inputs["Detail"].default_value = 10.0
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 22.0, 1.0)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], grain.inputs["Vector"])
    shade = nt.nodes.new("ShaderNodeMapRange")
    shade.inputs["To Min"].default_value = 0.75
    shade.inputs["To Max"].default_value = 1.15
    nt.links.new(grain.outputs["Fac"], shade.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    lib.sock(mix.inputs, "Factor_Float").default_value = 1.0
    nt.links.new(brick.outputs["Color"], lib.sock(mix.inputs, "A_Color"))
    nt.links.new(shade.outputs["Result"], lib.sock(mix.inputs, "B_Color"))
    # Large-scale wear and dirt, darker into the corners (ambient occlusion).
    wear = nt.nodes.new("ShaderNodeTexNoise")
    wear.inputs["Scale"].default_value = 0.35
    wear.inputs["Detail"].default_value = 4.0
    nt.links.new(coord.outputs["Object"], wear.inputs["Vector"])
    wear_map = nt.nodes.new("ShaderNodeMapRange")
    wear_map.inputs["To Min"].default_value = 0.6
    wear_map.inputs["To Max"].default_value = 1.12
    nt.links.new(wear.outputs["Fac"], wear_map.inputs["Value"])
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 1.2
    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = 'RGBA'
    mix2.blend_type = 'MULTIPLY'
    lib.sock(mix2.inputs, "Factor_Float").default_value = 1.0
    nt.links.new(lib.sock(mix.outputs, "Result_Color"), lib.sock(mix2.inputs, "A_Color"))
    nt.links.new(wear_map.outputs["Result"], lib.sock(mix2.inputs, "B_Color"))
    mix3 = nt.nodes.new("ShaderNodeMix")
    mix3.data_type = 'RGBA'
    mix3.blend_type = 'MULTIPLY'
    lib.sock(mix3.inputs, "Factor_Float").default_value = 0.85
    nt.links.new(lib.sock(mix2.outputs, "Result_Color"), lib.sock(mix3.inputs, "A_Color"))
    nt.links.new(ao.outputs["AO"], lib.sock(mix3.inputs, "B_Color"))
    nt.links.new(lib.sock(mix3.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(brick.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def cloth(name, color, rough=0.95):
    return lib.material(name, lib.lin(color), rough=rough, noise_var=0.2, noise_scale=25, bump=0.25, bump_scale=90)


def rug_material(name, base, border, accent="#2a3a5a"):
    """Woven rug: a border band and a diamond field, from the object's 0-1 coordinates."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs["Vector"])

    def math_node(op, a, b=None, value=None):
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = op
        nt.links.new(a, m.inputs[0])
        if b is not None:
            nt.links.new(b, m.inputs[1])
        elif value is not None:
            m.inputs[1].default_value = value
        return m.outputs[0]

    dx = math_node('ABSOLUTE', math_node('SUBTRACT', sep.outputs["X"], value=0.5))
    dy = math_node('ABSOLUTE', math_node('SUBTRACT', sep.outputs["Y"], value=0.5))
    # Diamonds: |x| * aspect + |y| repeating.
    diamond = math_node('FRACT', math_node('MULTIPLY', math_node('ADD', math_node('MULTIPLY', dx, value=1.7), dy),
                                           value=5.0))
    edge = math_node('MAXIMUM', dx, dy)
    field = nt.nodes.new("ShaderNodeMix")
    field.data_type = 'RGBA'
    nt.links.new(math_node('GREATER_THAN', diamond, value=0.72), lib.sock(field.inputs, "Factor_Float"))
    lib.sock(field.inputs, "A_Color").default_value = (*lib.lin(base), 1)
    lib.sock(field.inputs, "B_Color").default_value = (*lib.lin(accent), 1)
    out = nt.nodes.new("ShaderNodeMix")
    out.data_type = 'RGBA'
    nt.links.new(math_node('GREATER_THAN', edge, value=0.4), lib.sock(out.inputs, "Factor_Float"))
    nt.links.new(lib.sock(field.outputs, "Result_Color"), lib.sock(out.inputs, "A_Color"))
    lib.sock(out.inputs, "B_Color").default_value = (*lib.lin(border), 1)
    nt.links.new(lib.sock(out.outputs, "Result_Color"), bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.3
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 300.0
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def flame_material():
    return lib.material("Flame", lib.lin("#ffb347"), emission=lib.lin("#ff9a2e"), emission_strength=14.0)


def glow_material(name, color, strength):
    return lib.material(name, lib.lin(color), emission=lib.lin(color), emission_strength=strength)


# --------------------------------------------------------------------------
# Small set pieces shared by rooms and furniture
# --------------------------------------------------------------------------

def mug(name, loc, parent, wood):
    o = lib.primitive("cylinder", name, mat=wood, parent=parent, radius=0.045, depth=0.12, location=loc, vertices=12)
    return o


def jar(name, loc, parent, color, h=0.18, r=0.06):
    mat = lib.material(name + "Mat", lib.lin(color), rough=0.3, spec=0.6)
    o = lib.primitive("cylinder", name, mat=mat, parent=parent, radius=r, depth=h,
                      location=(loc[0], loc[1], loc[2] + h / 2), vertices=14)
    lib.primitive("cylinder", name + "Lid", mat=rp.wood_material("Cork", "#9a7a4a"), parent=parent,
                  radius=r * 0.7, depth=0.03, location=(loc[0], loc[1], loc[2] + h + 0.015), vertices=10)
    return o


def candle(name, loc, parent):
    lib.primitive("cylinder", name, mat=lib.material("Wax", lib.lin("#efe4c8"), rough=0.5, subsurface=0.3),
                  parent=parent, radius=0.025, depth=0.14, location=(loc[0], loc[1], loc[2] + 0.07), vertices=10)
    lib.primitive("uv_sphere", name + "Flame", mat=flame_material(), parent=parent, radius=0.02,
                  location=(loc[0], loc[1], loc[2] + 0.17)).scale = (1, 1, 1.8)


def drawer_front(name, x, y, z, w, h, wood, knob, parent):
    lib.box(name, (w, 0.03, h), (x, y, z), mat=wood, parent=parent, bevel=0.01)
    lib.primitive("uv_sphere", name + "Knob", mat=knob, parent=parent, radius=0.022, location=(x, y - 0.03, z))


# --------------------------------------------------------------------------
# Furniture (props)
# --------------------------------------------------------------------------

def chest(variant=0):
    root = furniture_setup()
    wood = rp.wood_material("ChestWood", ("#6b4a2b", "#4a3420")[variant])
    iron = rp.iron_material()
    w, d, h = 0.95, 0.56, 0.48
    lib.box("Body", (w, d, h), (0, 0.1, h / 2), mat=wood, parent=root, bevel=0.02)
    lid = lib.primitive("cylinder", "Lid", mat=wood, parent=root, radius=d / 2, depth=w, vertices=24,
                        location=(0, 0.1, h))
    lid.rotation_euler = (0, math.radians(90), 0)
    lid.scale = (1, 1, 1)
    lib.box("LidCut", (w + 0.1, d + 0.1, 0.3), (0, 0.1, h - 0.15), parent=root).hide_render = True
    cut = lid.modifiers.new("Half", 'BOOLEAN')
    cut.object = bpy.data.objects["LidCut"]
    cut.operation = 'DIFFERENCE'
    if variant == 0:
        for x in (-0.33, 0.0, 0.33):
            lib.box(f"Band{x}", (0.06, d + 0.02, h + 0.01), (x, 0.1, h / 2), mat=iron, parent=root)
            band = lib.primitive("cylinder", f"LidBand{x}", mat=iron, parent=root, radius=d / 2 + 0.01, depth=0.06,
                                 vertices=24, location=(x, 0.1, h))
            band.rotation_euler = (0, math.radians(90), 0)
            m = band.modifiers.new("Half", 'BOOLEAN')
            m.object = bpy.data.objects["LidCut"]
            m.operation = 'DIFFERENCE'
    lib.box("Lock", (0.12, 0.03, 0.14), (0, 0.1 - d / 2 - 0.01, h - 0.02), mat=rp.iron_material(), parent=root)
    rp.finish("chest", root, variant=variant)


def dresser():
    root = furniture_setup()
    wood = rp.wood_material("DresserWood", "#5e3f25")
    front = rp.wood_material("DrawerWood", "#6e4b2c")
    knob = lib.material("Brass", lib.lin("#c99a3e"), rough=0.3, metallic=1.0)
    w, d, h = 1.1, 0.5, 1.0
    lib.box("Carcass", (w, d, h), (0, 0.18, h / 2 + 0.05), mat=wood, parent=root, bevel=0.015)
    lib.box("Top", (w + 0.06, d + 0.05, 0.05), (0, 0.18, h + 0.075), mat=wood, parent=root, bevel=0.01)
    for i, z in enumerate((0.27, 0.57, 0.86)):
        for x in (-0.27, 0.27):
            drawer_front(f"Drawer{i}{x}", x, 0.18 - d / 2 - 0.01, z, 0.5, 0.25, front, knob, root)
    for x in (-0.5, 0.5):
        lib.box(f"Foot{x}", (0.08, 0.08, 0.06), (x, 0.0, 0.03), mat=wood, parent=root)
    candle("Candle", (-0.3, 0.25, h + 0.1), root)
    jar("Jug", (0.25, 0.2, h + 0.1), root, "#8a6a4a", h=0.24, r=0.07)
    rp.finish("dresser", root)


def cupboard(variant=0):
    root = furniture_setup()
    wood = rp.wood_material("CupWood", ("#4e3520", "#6a4a2c")[variant])
    w, d, h = 1.2, 0.48, 1.95
    y = 0.2
    lib.box("Back", (w, 0.05, h), (0, y + d / 2 - 0.025, h / 2), mat=wood, parent=root)
    for x in (-w / 2 + 0.03, w / 2 - 0.03):
        lib.box(f"Side{x}", (0.06, d, h), (x, y, h / 2), mat=wood, parent=root, bevel=0.01)
    lib.box("Cornice", (w + 0.1, d + 0.08, 0.08), (0, y, h + 0.04), mat=wood, parent=root, bevel=0.02)
    lib.box("Bottom", (w, d, 0.1), (0, y, 0.05), mat=wood, parent=root)
    if variant == 0:
        # Closed doors over the lower half, plates on open upper shelves.
        lib.box("Doors", (w - 0.1, 0.04, 0.85), (0, y - d / 2 + 0.02, 0.52), mat=wood, parent=root, bevel=0.01)
        lib.box("Split", (0.02, 0.05, 0.8), (0, y - d / 2 + 0.01, 0.52), mat=rp.wood_material("Dk", "#2e2014"),
                parent=root)
        knob = lib.material("Brass", lib.lin("#c99a3e"), rough=0.3, metallic=1.0)
        for x in (-0.06, 0.06):
            lib.primitive("uv_sphere", f"Knob{x}", mat=knob, parent=root, radius=0.02, location=(x, y - d / 2 - 0.02, 0.6))
        plate = lib.material("Pewter", lib.lin("#9a9890"), rough=0.35, metallic=0.8)
        for z in (1.05, 1.5):
            lib.box(f"Shelf{z}", (w - 0.1, d - 0.05, 0.03), (0, y, z), mat=wood, parent=root)
            for k in range(4):
                p = lib.primitive("cylinder", f"Plate{z}{k}", mat=plate, parent=root, radius=0.12, depth=0.015,
                                  location=(-0.4 + k * 0.27, y + 0.12, z + 0.14), vertices=20)
                p.rotation_euler = (math.radians(75), 0, 0)
    else:
        # Open shelves of jars and bottles (an apothecary's).
        r = np.random.default_rng(7)
        colors = ("#3a6a3a", "#7a2a2a", "#2a4a7a", "#8a7a3a", "#5a3a6a", "#c8b890")
        for z in (0.1, 0.55, 1.0, 1.45):
            lib.box(f"Shelf{z}", (w - 0.1, d - 0.05, 0.03), (0, y, z), mat=wood, parent=root)
            x = -0.47
            while x < 0.47:
                hh = r.uniform(0.12, 0.26)
                rr = r.uniform(0.04, 0.065)
                jar(f"Jar{z}{x:.2f}", (x + rr, y + r.uniform(-0.05, 0.05), z + 0.015), root,
                    colors[r.integers(len(colors))], h=hh, r=rr)
                x += rr * 2 + r.uniform(0.02, 0.06)
    rp.finish("cupboard", root, variant=variant)


def table():
    """Table with benches front and back, on a 2x2 hex footprint."""
    root = furniture_setup()
    wood = rp.wood_material("TableWood", "#6b4a2b")
    depth = rp.footprint_depth(2)
    cy = depth / 2
    lib.box("Top", (1.9, 0.9, 0.07), (0, cy, 0.78), mat=wood, parent=root, bevel=0.015)
    for sx in (-0.82, 0.82):
        lib.box(f"Trestle{sx}", (0.08, 0.7, 0.72), (sx, cy, 0.38), mat=wood, parent=root)
        lib.box(f"TFoot{sx}", (0.12, 0.8, 0.08), (sx, cy, 0.04), mat=wood, parent=root)
    lib.box("Stretcher", (1.6, 0.06, 0.08), (0, cy, 0.25), mat=wood, parent=root)
    for side in (-1, 1):
        by = cy + side * 0.72
        lib.box(f"Bench{side}", (1.7, 0.3, 0.05), (0, by, 0.46), mat=wood, parent=root, bevel=0.01)
        for sx in (-0.7, 0.7):
            lib.box(f"BLeg{side}{sx}", (0.06, 0.24, 0.44), (sx, by, 0.22), mat=wood, parent=root)
    plate = lib.material("Pewter", lib.lin("#9a9890"), rough=0.35, metallic=0.8)
    for k, (x, y) in enumerate(((-0.55, -0.2), (0.45, 0.22), (0.1, -0.18))):
        lib.primitive("cylinder", f"Plate{k}", mat=plate, parent=root, radius=0.13, depth=0.02,
                      location=(x, cy + y, 0.825), vertices=20)
        mug(f"Mug{k}", (x + 0.2, cy + y + 0.08, 0.875), root, rp.wood_material("MugWood", "#8a6a44"))
    bread = lib.primitive("uv_sphere", "Bread", mat=lib.material("Crust", lib.lin("#a8743a"), rough=0.7),
                          parent=root, radius=0.12, location=(-0.1, cy + 0.15, 0.86))
    bread.scale = (1.4, 0.9, 0.6)
    candle("Candle", (0.65, cy - 0.05, 0.815), root)
    rp.finish("table", root)


def bed():
    """A bed along a 2x1 hex footprint, headboard to the left."""
    root = furniture_setup()
    wood = rp.wood_material("BedWood", "#5a3c24")
    cy = rp.footprint_depth(1) / 2
    lib.box("Frame", (2.0, 1.0, 0.32), (0, cy, 0.22), mat=wood, parent=root, bevel=0.02)
    lib.box("Head", (0.08, 1.05, 0.95), (-1.0, cy, 0.48), mat=wood, parent=root, bevel=0.02)
    lib.box("Foot", (0.08, 1.05, 0.55), (1.0, cy, 0.28), mat=wood, parent=root, bevel=0.02)
    lib.box("Mattress", (1.88, 0.9, 0.16), (0, cy, 0.45), mat=cloth("Linen", "#d8cdb2"), parent=root, bevel=0.05)
    blanket = lib.box("Blanket", (1.25, 0.96, 0.1), (0.3, cy, 0.52), mat=cloth("Blanket", "#7a2e24"), parent=root,
                      bevel=0.04)
    blanket.name = "Blanket"
    pillow = lib.primitive("uv_sphere", "Pillow", mat=cloth("Pillow", "#e8e0cc"), parent=root, radius=0.25,
                           location=(-0.72, cy, 0.58))
    pillow.scale = (0.7, 1.4, 0.4)
    rp.finish("bed", root)


def bar_counter():
    """The inn's bar along a 4x1 hex footprint, with mugs and a keg."""
    root = furniture_setup()
    wood = rp.wood_material("BarWood", "#4e3420")
    top = rp.wood_material("BarTop", "#6e4c2e")
    cy = rp.footprint_depth(1) / 2
    lib.box("Body", (5.4, 0.62, 1.0), (0, cy, 0.5), mat=wood, parent=root, bevel=0.02)
    lib.box("Top", (5.6, 0.75, 0.07), (0, cy, 1.04), mat=top, parent=root, bevel=0.02)
    for k in range(8):
        lib.box(f"Panel{k}", (0.55, 0.03, 0.7), (-2.4 + k * 0.685, cy - 0.32, 0.48), mat=top, parent=root, bevel=0.01)
    mw = rp.wood_material("MugWood", "#8a6a44")
    for k, x in enumerate((-2.2, -1.9, -0.6, 0.4, 1.5, 1.7)):
        mug(f"Mug{k}", (x, cy - 0.05 + (k % 2) * 0.12, 1.135), root, mw)
    keg = rp.barrel_mesh("Keg", (2.3, cy + 0.05, 1.07), wood, rp.iron_material(), root, h=0.55, r=0.24, lying=True)
    keg.name = "Keg"
    candle("Candle", (-1.2, cy + 0.1, 1.075), root)
    rp.finish("bar_counter", root)


def anvil():
    root = furniture_setup()
    stump = rp.bark_material("Stump", "#4a3a2a")
    lib.cylinder_between("Block", (0, 0.05, 0), (0, 0.05, 0.5), 0.3, mat=stump, parent=root, sides=16)
    iron = lib.material("AnvilIron", lib.lin("#3a3836"), rough=0.4, metallic=0.9)
    lib.box("Waist", (0.22, 0.18, 0.2), (0, 0.05, 0.6), mat=iron, parent=root)
    lib.box("Face", (0.55, 0.22, 0.13), (0.03, 0.05, 0.765), mat=iron, parent=root, bevel=0.02)
    horn = lib.cylinder_between("Horn", (-0.25, 0.05, 0.77), (-0.55, 0.05, 0.8), 0.08, 0.01, mat=iron, parent=root)
    horn.name = "Horn"
    lib.box("Hammer", (0.3, 0.04, 0.04), (0.12, 0.0, 0.85), mat=rp.wood_material("H", "#6a4a2a"), parent=root)
    lib.box("HammerHead", (0.06, 0.06, 0.09), (0.26, 0.0, 0.87), mat=iron, parent=root)
    rp.finish("anvil", root)


def rug():
    """A woven rug on a 3x2 hex footprint (ground layer, walkable)."""
    root = furniture_setup()
    depth = rp.footprint_depth(2)
    lib.box("Rug", (3.6, depth * 0.85, 0.015), (0, depth / 2, 0.0075),
            mat=rug_material("Rug", "#6e3226", "#9a7a46", accent="#2e3546"), parent=root)
    rp.finish("rug", root)


def bar_back():
    """Shelves of bottles and mugs that stand behind a bar, against the back
    wall (3x1 hexes). Part of the "bar" furnishing add-on."""
    root = furniture_setup()
    wood = rp.wood_material("ShelfWood", "#4a3220")
    depth = rp.footprint_depth(1)
    y = depth - 0.15
    w = 3 * lib.HEX_M - 0.4
    lib.box("Back", (w, 0.05, 2.1), (0, y + 0.2, 1.05), mat=wood, parent=root)
    for x in (-w / 2, w / 2):
        lib.box(f"Side{x}", (0.07, 0.42, 2.1), (x, y, 1.05), mat=wood, parent=root, bevel=0.01)
    lib.box("Cornice", (w + 0.12, 0.5, 0.08), (0, y, 2.14), mat=wood, parent=root, bevel=0.02)
    lib.box("Base", (w, 0.42, 0.5), (0, y, 0.25), mat=wood, parent=root, bevel=0.01)
    bar_shelves(-w / 2 + 0.05, w / 2 - 0.05, y + 0.15, root, wood)
    rp.finish("bar_back", root)


def item_pile():
    """Things dropped on the ground: a sack, a bundle and a glint of metal."""
    root = furniture_setup()
    sack = lib.primitive("uv_sphere", "Sack", mat=cloth("Sack", "#8a7450"), parent=root, radius=0.2,
                         location=(-0.05, 0.05, 0.16))
    sack.scale = (1.0, 0.9, 0.85)
    lib.cylinder_between("Neck", (-0.05, 0.05, 0.28), (-0.03, 0.06, 0.38), 0.06, 0.04,
                         mat=cloth("Sack2", "#7a6444"), parent=root, sides=10)
    lib.cylinder_between("Tie", (-0.04, 0.055, 0.31), (-0.04, 0.055, 0.33), 0.065,
                         mat=cloth("Cord", "#3a2a1a"), parent=root, sides=10)
    roll = lib.cylinder_between("Bedroll", (0.05, -0.12, 0.08), (0.42, 0.02, 0.08), 0.08,
                                mat=cloth("Roll", "#5a3a2a"), parent=root, sides=14)
    roll.name = "Bedroll"
    steel = lib.material("Steel", lib.lin("#b8bcc2"), rough=0.3, metallic=1.0)
    lib.box("Blade", (0.5, 0.04, 0.012), (0.1, -0.22, 0.02), mat=steel, parent=root,
            rotation=(0, 0, math.radians(-12)))
    lib.box("Hilt", (0.03, 0.12, 0.03), (-0.17, -0.17, 0.03), mat=lib.material("Brass", lib.lin("#c99a3e"),
                                                                              rough=0.3, metallic=1.0),
            parent=root, rotation=(0, 0, math.radians(-12)))
    rp.finish("item_pile", root)


def door_exit():
    """Rush mat and a spill of daylight at an interior's door (walkable)."""
    root = furniture_setup()
    rush = lib.material("Rush", lib.lin("#8a7a4a"), rough=1.0, noise_var=0.35, noise_scale=40, bump=0.6,
                        bump_scale=120)
    lib.box("Mat", (0.95, 0.55, 0.025), (0, 0.0, 0.0125), mat=rush, parent=root, bevel=0.03)
    lib.box("Edge", (1.0, 0.6, 0.015), (0, 0.0, 0.0075), mat=cloth("MatEdge", "#5a4a2a"), parent=root, bevel=0.02)
    rp.finish("door_exit", root)


# --------------------------------------------------------------------------
# Rooms (backdrops)
# --------------------------------------------------------------------------

ROOMS = {
    # name: cols, rows, walls, floor, exit fraction across the front, features
    "cottage_plaster": dict(cols=8, rows=6, walls="plaster", timber="#4a3322", floor="planks",
                            exit=(3.5 / 6), hearth=0.2, windows=(0.55, 0.85), shelf=0.7),
    "cottage_stone": dict(cols=8, rows=6, walls="stone", timber="#3e2c1e", floor="flags",
                          exit=(2.5 / 6), hearth=0.78, windows=(0.2, 0.45), shelf=0.33),
    "cottage_timber": dict(cols=8, rows=6, walls="dark", timber="#2e2218", floor="planks",
                           exit=(4.5 / 6), hearth=0.25, windows=(0.55, 0.85), shelf=0.7),
    "smithy": dict(cols=8, rows=6, walls="stone", timber="#2e2218", floor="flags",
                   exit=(2.5 / 6), forge=0.72, windows=(0.25,), shelf=0.45),
    "inn_hall": dict(cols=12, rows=8, walls="plaster", timber="#3a2818", floor="planks",
                     exit=(4.5 / 9), hearth=0.82, windows=(0.15, 0.38), shelf=0.6),
}

WALL_H = 2.7
WALL_T = 0.35
LEAN = 0.9


def wall_material(kind, variant_name):
    if kind == "stone":
        return rp.stone_material("Walls" + variant_name, "#8a8274", scale=2.4)
    if kind == "dark":
        return rp.plaster_material("Walls" + variant_name, "#bfb299")
    return rp.plaster_material("Walls" + variant_name, "#d6cbb0")


def leaning_wall(name, x_floor, x_top, y0, y1, mat, parent):
    """Side wall whose inner face leans outward so the camera can see it."""
    t = WALL_T if x_top < x_floor else -WALL_T
    v = [(x_floor, y0, 0), (x_floor, y1, 0), (x_top, y1, WALL_H), (x_top, y0, WALL_H),
         (x_floor - t, y0, 0), (x_floor - t, y1, 0), (x_top - t, y1, WALL_H), (x_top - t, y0, WALL_H)]
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (3, 2, 6, 7), (0, 3, 7, 4), (1, 5, 6, 2), (0, 4, 5, 1)]
    return lib.mesh_object(name, v, f, mat=mat, parent=parent)


def window_on_wall(name, x, y, parent, timber):
    glass = glow_material(name + "Glass", "#dfe8f0", 2.2)
    lib.box(name + "Frame", (1.0, 0.1, 1.05), (x, y - 0.03, 1.55), mat=timber, parent=parent, bevel=0.02)
    lib.box(name + "Pane", (0.82, 0.1, 0.87), (x, y - 0.06, 1.55), mat=glass, parent=parent)
    lib.box(name + "Mull", (0.05, 0.12, 0.87), (x, y - 0.08, 1.55), mat=timber, parent=parent)
    lib.box(name + "Sill", (1.1, 0.2, 0.06), (x, y - 0.1, 1.0), mat=timber, parent=parent)
    data = bpy.data.lights.new(name + "Light", 'AREA')
    data.energy = 200.0
    data.size = 1.0
    data.color = (0.85, 0.9, 1.0)
    obj = bpy.data.objects.new(name + "Light", data)
    lib.link(obj, parent)
    obj.location = (x, y - 0.3, 1.6)
    obj.rotation_euler = (math.radians(-60), 0, 0)


def hearth(x, y, parent, stone, timber):
    lib.box("HearthBreast", (1.9, 0.6, WALL_H + 0.1), (x, y - 0.25, (WALL_H + 0.1) / 2), mat=stone, parent=parent)
    lib.box("HearthHole", (1.15, 0.2, 0.95), (x, y - 0.5, 0.48), mat=lib.material("Soot", lib.lin("#120c08"), rough=1),
            parent=parent)
    lib.box("Mantel", (2.1, 0.32, 0.14), (x, y - 0.6, 1.12), mat=timber, parent=parent, bevel=0.02)
    lib.box("Hearthstone", (2.0, 0.6, 0.06), (x, y - 0.85, 0.03), mat=stone, parent=parent)
    fire = flame_material()
    for k, (dx, h) in enumerate(((-0.2, 0.35), (0.05, 0.45), (0.25, 0.3))):
        f = lib.primitive("cone", f"Fire{k}", mat=fire, parent=parent, radius1=0.16, depth=h,
                          location=(x + dx, y - 0.55, 0.1 + h / 2))
        f.name = f"Fire{k}"
    logs = rp.bark_material("FireLogs", "#3a2a1a")
    for k in (-1, 1):
        lib.cylinder_between(f"FireLog{k}", (x - 0.35, y - 0.5 + k * 0.05, 0.08), (x + 0.35, y - 0.6 - k * 0.05, 0.1),
                             0.06, mat=logs, parent=parent, sides=8)
    point_light("HearthLight", (x, y - 1.0, 0.6), 650.0, (1.0, 0.55, 0.22), radius=0.4, parent=parent)
    for k in range(3):  # pots on the mantel
        jar(f"MantelJar{k}", (x - 0.6 + k * 0.6, y - 0.62, 1.19), parent, ("#6a5a4a", "#8a7a5a", "#4a5a6a")[k],
            h=0.2, r=0.07)


def forge(x, y, parent, stone):
    brick = rp.stone_material("ForgeBrick", "#7a4a3a", scale=6.0)
    lib.box("Forge", (2.0, 1.1, 0.85), (x, y - 0.6, 0.43), mat=brick, parent=parent, bevel=0.03)
    lib.box("Hood", (1.7, 0.9, 1.4), (x, y - 0.4, 2.0), mat=brick, parent=parent)
    coals = glow_material("Coals", "#ff5a1a", 9.0)
    lib.box("Coals", (1.2, 0.6, 0.06), (x, y - 0.6, 0.87), mat=coals, parent=parent)
    point_light("ForgeLight", (x, y - 1.1, 1.2), 650.0, (1.0, 0.45, 0.15), radius=0.5, parent=parent)
    tools = rp.iron_material()
    for k in range(4):
        lib.box(f"Tong{k}", (0.04, 0.03, 0.6), (x + 1.25 + k * 0.12, y - 0.05, 1.5), mat=tools, parent=parent)


def bar_shelves(x0, x1, y, parent, timber):
    r = np.random.default_rng(3)
    for z in (1.3, 1.75, 2.2):
        lib.box(f"BarShelf{z}", (x1 - x0, 0.3, 0.05), ((x0 + x1) / 2, y - 0.15, z), mat=timber, parent=parent)
        x = x0 + 0.15
        while x < x1 - 0.15:
            if r.random() < 0.6:
                jar(f"Bottle{z}{x:.2f}", (x, y - 0.15, z + 0.025), parent,
                    ("#2a4a2a", "#5a2a1a", "#6a5a3a", "#2a2a4a")[r.integers(4)], h=r.uniform(0.2, 0.3), r=0.045)
            else:
                mug(f"ShelfMug{z}{x:.2f}", (x, y - 0.15, z + 0.085), parent, rp.wood_material("MugWood", "#8a6a44"))
            x += r.uniform(0.14, 0.24)


def hanging_herbs(x, y, parent):
    herb = lib.material("Herbs", lib.lin("#5a6a3a"), rough=0.9, noise_var=0.3)
    for k in range(5):
        lib.cylinder_between(f"Herb{x}{k}", (x + k * 0.18, y - 0.1, 2.35), (x + k * 0.18, y - 0.12, 1.95), 0.05, 0.02,
                             mat=herb, parent=parent, sides=6)


def wall_shelf(x, y, parent, timber):
    lib.box("WallShelf", (1.4, 0.25, 0.05), (x, y - 0.13, 1.8), mat=timber, parent=parent)
    for k, c in enumerate(("#7a6a52", "#5a6a7a", "#8a5a3a", "#6a7a4a")):
        jar(f"ShelfPot{k}", (x - 0.5 + k * 0.33, y - 0.13, 1.825), parent, c, h=0.16 + 0.04 * (k % 2), r=0.07)


def room(name):
    spec = ROOMS[name]
    cols, rows = spec["cols"], spec["rows"]
    root = room_setup()
    w = lib.HEX_M
    r = lib.HEX_M / math.sqrt(3)
    # Floor covers every hex of a cols x rows odd-r map, hex [0, 0] at the origin.
    x0, x1 = -w / 2 - 0.05, w * cols + 0.05
    yb, yf = r + 0.05, -(rows - 1) * lib.ROW_M - r - 0.05
    floor = plank_floor("Floor", "#7a5636") if spec["floor"] == "planks" else \
        rp.stone_material("Flags", "#6f685d", scale=2.2, mortar="#2e2a25")
    lib.box("Floor", (x1 - x0 + 1.0, yb - yf, 0.1), ((x0 + x1) / 2, (yb + yf) / 2, -0.05), mat=floor, parent=root)
    walls = wall_material(spec["walls"], name)
    timber = rp.wood_material("Timber", spec["timber"])
    stone = rp.stone_material("HearthStone", "#7d776c", scale=3.5)
    # Back wall, with a timber frame on plaster walls.
    lib.box("BackWall", (x1 - x0 + 2 * LEAN + 2 * WALL_T, WALL_T, WALL_H),
            ((x0 + x1) / 2, yb + WALL_T / 2, WALL_H / 2), mat=walls, parent=root)
    lib.box("BackBeam", (x1 - x0 + 2 * LEAN, 0.18, 0.22), ((x0 + x1) / 2, yb - 0.05, WALL_H - 0.11), mat=timber,
            parent=root, bevel=0.02)
    lib.box("Skirting", (x1 - x0, 0.06, 0.12), ((x0 + x1) / 2, yb - 0.02, 0.06), mat=timber, parent=root)
    if spec["walls"] != "stone":
        n_posts = max(3, round((x1 - x0) / 2.4))
        for k in range(n_posts + 1):
            px = x0 + (x1 - x0) * k / n_posts
            lib.box(f"Post{k}", (0.2, 0.16, WALL_H), (px, yb - 0.04, WALL_H / 2), mat=timber, parent=root, bevel=0.02)
    leaning_wall("LeftWall", x0, x0 - LEAN, yf, yb + WALL_T, walls, root)
    leaning_wall("RightWall", x1, x1 + LEAN, yf, yb + WALL_T, walls, root)
    for side, (xa, xb) in (("L", (x0, x0 - LEAN)), ("R", (x1, x1 + LEAN))):
        lib.cylinder_between(f"TopPlate{side}", (xb, yf, WALL_H), (xb, yb, WALL_H), 0.1, mat=timber, parent=root,
                             sides=4)
    # Front sill with a gap at the door.
    exit_x = x0 + (x1 - x0) * spec["exit"]
    exit_col = int(round(exit_x / w - 0.5))  # bottom row is odd: centres at w * (col + 0.5)
    exit_x = w * (exit_col + 0.5)
    for k, (a, b) in enumerate(((x0 - LEAN, exit_x - 0.65), (exit_x + 0.65, x1 + LEAN))):
        lib.box(f"Sill{k}", (b - a, WALL_T, 0.32), ((a + b) / 2, yf - WALL_T / 2, 0.16), mat=walls, parent=root)
        lib.box(f"SillCap{k}", (b - a, WALL_T + 0.04, 0.06), ((a + b) / 2, yf - WALL_T / 2, 0.33), mat=timber,
                parent=root)
    lib.box("Threshold", (1.3, WALL_T, 0.04), (exit_x, yf - WALL_T / 2, 0.02),
            mat=rp.stone_material("Threshold", "#8e897e", scale=2.0), parent=root)
    # Back-wall features.
    def wx(f):
        return x0 + (x1 - x0) * f
    for k, f in enumerate(spec.get("windows", ())):
        window_on_wall(f"Win{k}", wx(f), yb, root, timber)
    if "hearth" in spec:
        hearth(wx(spec["hearth"]), yb, root, stone, timber)
    if "forge" in spec:
        forge(wx(spec["forge"]), yb, root, stone)
    if "bar_shelves" in spec:
        a, b = spec["bar_shelves"]
        bar_shelves(wx(a), wx(b), yb, root, timber)
    else:
        hanging_herbs(wx(0.05) + 0.3, yb, root)
        wall_shelf(wx(spec.get("shelf", 0.4)), yb, root, timber)
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.hide_render]
    cam, res = lib.frame_oblique(objs, margin_px=4)
    path = lib.ASSETS / "interiors" / f"{name}.png"
    lib.render(path, res=res)
    origin = lib.to_pixel(cam, root.matrix_world @ Vector((0, 0, 0)), res)
    # Back-row columns in front of the hearth or forge, which furniture should leave clear.
    keep = set()
    for key in ("hearth", "forge"):
        if key in spec:
            cx = wx(spec[key]) / w
            keep |= {int(math.floor(cx - 0.6)), int(round(cx)), int(math.ceil(cx + 0.6)) - 1}
    BACKDROPS[name] = {"texture": f"res://assets/interiors/{name}.png", "origin": [round(origin[0]), round(origin[1])],
                       "size": [cols, rows], "exit": [exit_col, rows - 1], "keep_clear": sorted(keep)}
    print("wrote", path, res, BACKDROPS[name])


def write_backdrops():
    path = lib.ASSETS / "interiors" / "backdrops.json"
    data = json.loads(path.read_text()) if path.exists() else {}
    data.update(BACKDROPS)
    path.write_text(json.dumps(data, indent="\t") + "\n")
    print("updated", path)


def variants(fn, n):
    return [lambda i=i: fn(i) for i in range(n)]


FURNITURE = {
    "chest": variants(chest, 2),
    "dresser": [dresser],
    "cupboard": variants(cupboard, 2),
    "table": [table],
    "bed": [bed],
    "bar_counter": [bar_counter],
    "anvil": [anvil],
    "rug": [rug],
    "door_exit": [door_exit],
    "bar_back": [bar_back],
    "item_pile": [item_pile],
}


def run(names=None):
    names = names or list(FURNITURE) + list(ROOMS)
    for name in names:
        if name in FURNITURE:
            for fn in FURNITURE[name]:
                fn()
        elif name in ROOMS:
            room(name)
    if any(n in FURNITURE for n in names):
        rp.write_manifest()
    if any(n in ROOMS for n in names):
        write_backdrops()
