"""Shared helpers for the Blender (bpy) asset renderer.

Assets are modelled procedurally and pre-rendered with Cycles, the way classic
isometric RPGs pre-rendered their art. Conventions:

- 1 Blender unit = 1 metre. One hex is 5 ft (1.524 m) and 55.4 px wide, so the
  game scale is PX_PER_M pixels per metre.
- Props and characters are seen by an orthographic camera looking north,
  ELEVATION degrees above the horizon. Models are parented to an "oblique"
  root that stretches depth (y) by 1/sin(ELEVATION), so ground footprints
  come out at the same pixel size as the game's top-down hex grid while
  walls and bodies keep their height.
- Light comes from the upper left of the screen; shadows fall down-right.
"""
import math
import random
from pathlib import Path

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Vector
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "assets"
HEX_RADIUS_PX = 32
HEX_W_PX = HEX_RADIUS_PX * math.sqrt(3)
HEX_M = 1.524
PX_PER_M = HEX_W_PX / HEX_M
ROW_M = HEX_M * 1.5 / math.sqrt(3)  # distance between hex rows in metres
ELEVATION = math.radians(45)
DEPTH_STRETCH = 1.0 / math.sin(ELEVATION)
SUPERSAMPLE = 2
# Direction sunlight travels: towards screen right (+x), towards the viewer (-y), down.
# Terrain uses a lower sun (more relief); props a high one so shadows stay compact.
SUN_DIR_TERRAIN = Vector((0.62, -0.42, -0.66)).normalized()
SUN_DIR = Vector((0.388, -0.263, -0.883)).normalized()


# --------------------------------------------------------------------------
# Scene
# --------------------------------------------------------------------------

def reset_scene(samples=64, transparent=True, sky=(0.62, 0.70, 0.82), sky_strength=0.85):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.transparent_max_bounces = 8
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    sc.render.threads_mode = 'AUTO'
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*sky, 1.0)
    bg.inputs[1].default_value = sky_strength
    return sc


def add_sun(strength=3.4, angle_deg=4.0, color=(1.0, 0.94, 0.84), direction=SUN_DIR):
    data = bpy.data.lights.new("Sun", 'SUN')
    data.energy = strength
    data.angle = math.radians(angle_deg)
    data.color = color
    obj = bpy.data.objects.new("Sun", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.rotation_euler = Vector(direction).to_track_quat('-Z', 'Y').to_euler()
    return obj


def oblique_root():
    """Empty that stretches depth so footprints match the top-down grid."""
    root = bpy.data.objects.new("Oblique", None)
    bpy.context.scene.collection.objects.link(root)
    root.scale = (1.0, DEPTH_STRETCH, 1.0)
    return root


def add_shadow_catcher(size=80.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    plane = bpy.context.object
    plane.name = "ShadowCatcher"
    plane.is_shadow_catcher = True
    return plane


def link(obj, parent=None):
    if obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


# --------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------

def mesh_object(name, verts, faces, colors=None, mat=None, smooth=False, parent=None):
    """Object from raw vertex/face lists. `colors` = per-vertex RGB (0-1)."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    if colors is not None:
        attr = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
        flat = np.ones((len(colors), 4), dtype=np.float32)
        flat[:, :3] = np.asarray(colors, dtype=np.float32)
        attr.data.foreach_set("color", flat.ravel())
    if smooth:
        me.shade_smooth()
    obj = bpy.data.objects.new(name, me)
    link(obj, parent)
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def box(name, size, location, mat=None, parent=None, rotation=(0, 0, 0), bevel=0.0, segments=2):
    sx, sy, sz = (s / 2 for s in size)
    v = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
         (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    obj = mesh_object(name, v, f, mat=mat, parent=parent)
    obj.location = location
    obj.rotation_euler = rotation
    if bevel > 0:
        m = obj.modifiers.new("Bevel", 'BEVEL')
        m.width = bevel
        m.segments = segments
    return obj


def primitive(kind, name, mat=None, parent=None, **kw):
    getattr(bpy.ops.mesh, f"primitive_{kind}_add")(**kw)
    obj = bpy.context.object
    obj.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
    return obj


def subsurf(obj, levels=2):
    m = obj.modifiers.new("Subsurf", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    return m


def displace(obj, strength=0.1, scale=1.0, kind='CLOUDS', mid=0.5, depth=2):
    tex = bpy.data.textures.new(obj.name + "_disp", kind)
    if hasattr(tex, "noise_scale"):
        tex.noise_scale = scale
    if hasattr(tex, "noise_depth"):
        tex.noise_depth = depth
    m = obj.modifiers.new("Displace", 'DISPLACE')
    m.texture = tex
    m.strength = strength
    m.mid_level = mid
    return m


def cylinder_between(name, a, b, r0, r1=None, mat=None, parent=None, sides=12):
    """Tapered cylinder from point a to point b."""
    r1 = r0 if r1 is None else r1
    a, b = Vector(a), Vector(b)
    axis = b - a
    length = axis.length
    rot = axis.to_track_quat('Z', 'Y').to_matrix()
    verts, faces = [], []
    for ring, (z, r) in enumerate(((0.0, r0), (length, r1))):
        for i in range(sides):
            ang = 2 * math.pi * i / sides
            p = Vector((math.cos(ang) * r, math.sin(ang) * r, z))
            verts.append(a + rot @ p)
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j, sides + i))
    faces.append(tuple(range(sides))[::-1])
    faces.append(tuple(range(sides, 2 * sides)))
    return mesh_object(name, verts, faces, mat=mat, parent=parent, smooth=True)


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

def sock(sockets, identifier):
    """Socket by identifier (names repeat on multi-type nodes such as Mix)."""
    for so in sockets:
        if so.identifier == identifier:
            return so
    raise KeyError(identifier)


def _principled(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    return nt, nt.nodes["Principled BSDF"]


def material(name, color, rough=0.8, metallic=0.0, spec=0.35, vcol=False, noise_var=0.0,
             noise_scale=8.0, bump=0.0, bump_scale=20.0, emission=None, emission_strength=0.0,
             transmission=0.0, alpha=1.0, subsurface=0.0):
    """Principled material with optional vertex colour, colour noise and bump."""
    mat = bpy.data.materials.new(name)
    nt, bsdf = _principled(mat)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = spec
    base = nt.nodes.new("ShaderNodeRGB")
    base.outputs[0].default_value = (*color, 1.0)
    color_out = base.outputs[0]
    if vcol:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        color_out = attr.outputs["Color"]
    if noise_var > 0:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = noise_scale
        tex.inputs["Detail"].default_value = 6.0
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        sock(mix.inputs, "Factor_Float").default_value = 1.0
        ramp = nt.nodes.new("ShaderNodeMapRange")
        ramp.inputs["To Min"].default_value = 1.0 - noise_var
        ramp.inputs["To Max"].default_value = 1.0 + noise_var * 0.6
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Value"])
        nt.links.new(color_out, sock(mix.inputs, "A_Color"))
        nt.links.new(ramp.outputs["Result"], sock(mix.inputs, "B_Color"))
        color_out = sock(mix.outputs, "Result_Color")
    nt.links.new(color_out, bsdf.inputs["Base Color"])
    if bump > 0:
        btex = nt.nodes.new("ShaderNodeTexNoise")
        btex.inputs["Scale"].default_value = bump_scale
        btex.inputs["Detail"].default_value = 8.0
        bnode = nt.nodes.new("ShaderNodeBump")
        bnode.inputs["Strength"].default_value = bump
        nt.links.new(btex.outputs["Fac"], bnode.inputs["Height"])
        nt.links.new(bnode.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if transmission > 0:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    if subsurface > 0:
        bsdf.inputs["Subsurface Weight"].default_value = subsurface
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    return mat


def image_from_array(name, arr):
    """Blender image from an HxWx3/4 float array in 0-1 (row 0 = top)."""
    h, w = arr.shape[:2]
    if arr.shape[2] == 3:
        arr = np.concatenate([arr, np.ones((h, w, 1))], axis=2)
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=True)
    img.pixels.foreach_set(np.flipud(arr).astype(np.float32).ravel())
    img.pack()
    return img


def image_material(name, color_img, bump_img=None, bump=0.3, rough=0.85, tile_m=1.0, spec=0.3,
                   normal_strength=1.0):
    """Material using repeating images mapped in world/object XY over `tile_m` metres."""
    mat = bpy.data.materials.new(name)
    nt, bsdf = _principled(mat)
    bsdf.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = spec
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0 / tile_m, 1.0 / tile_m, 1.0)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = color_img
    tex.extension = 'REPEAT'
    tex.interpolation = 'Cubic'
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if bump_img is not None:
        btex = nt.nodes.new("ShaderNodeTexImage")
        btex.image = bump_img
        btex.extension = 'REPEAT'
        btex.interpolation = 'Cubic'
        btex.image.colorspace_settings.name = 'Non-Color'
        nt.links.new(mapping.outputs["Vector"], btex.inputs["Vector"])
        bnode = nt.nodes.new("ShaderNodeBump")
        bnode.inputs["Strength"].default_value = bump
        bnode.inputs["Distance"].default_value = normal_strength
        nt.links.new(btex.outputs["Color"], bnode.inputs["Height"])
        nt.links.new(bnode.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# --------------------------------------------------------------------------
# Periodic noise (numpy) for tileable textures
# --------------------------------------------------------------------------

def tile_noise(n, seed, beta=2.0, aniso=(1.0, 1.0)):
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(n) * n
    kx, ky = np.meshgrid(f * aniso[0], f * aniso[1])
    k = np.sqrt(kx ** 2 + ky ** 2)
    k[0, 0] = 1.0
    amp = k ** (-beta / 2.0)
    amp[0, 0] = 0.0
    phase = rng.uniform(0, 2 * np.pi, (n, n))
    img = np.real(np.fft.ifft2(amp * np.exp(1j * phase)))
    return (img - img.mean()) / (img.std() + 1e-9)


def colorize(v, stops):
    v = np.clip(v, 0, 1)
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=float)
    out = np.zeros(v.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(v, pos, cols[:, c])
    return out


def hexcol(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_linear(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin(h):
    """Hex colour -> linear RGB tuple (Blender colour inputs are linear)."""
    return tuple(float(x) for x in srgb_to_linear(hexcol(h)))


# --------------------------------------------------------------------------
# Cameras and rendering
# --------------------------------------------------------------------------

def _camera(rotation):
    data = bpy.data.cameras.new("Camera")
    data.type = 'ORTHO'
    cam = bpy.data.objects.new("Camera", data)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    cam.rotation_euler = rotation
    return cam


def mesh_points(objs):
    """World-space vertices of the evaluated meshes (modifiers applied)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    pts = []
    for obj in objs:
        if obj.type != 'MESH':
            continue
        ev = obj.evaluated_get(depsgraph)
        me = ev.to_mesh()
        co = np.empty(len(me.vertices) * 3, dtype=np.float64)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        mw = np.array(ev.matrix_world)
        co = co @ mw[:3, :3].T + mw[:3, 3]
        pts.append(co)
        ev.to_mesh_clear()
    return np.concatenate(pts) if pts else np.zeros((0, 3))


def frame_oblique(objs, margin_px=6, extra=(0, 0, 0, 0), shadows=False):
    """Ortho camera at ELEVATION framing `objs` at game scale.
    extra = additional pixels (left, top, right, bottom). With shadows=True the
    frame also covers where the sun casts the objects' shadows on the ground."""
    cam = _camera(Euler((math.pi / 2 - ELEVATION, 0, 0)))
    bpy.context.view_layer.update()
    pts = mesh_points(objs)
    if shadows and len(pts):
        sun = np.array(SUN_DIR)
        up = pts[pts[:, 2] > 0.01]
        t = up[:, 2] / -sun[2]
        pts = np.concatenate([pts, up + t[:, None] * sun])
    rot = cam.rotation_euler.to_matrix()
    inv = rot.inverted()
    local = np.array([inv @ Vector(p) for p in pts])
    xmin, ymin = local[:, 0].min(), local[:, 1].min()
    xmax, ymax = local[:, 0].max(), local[:, 1].max()
    s = PX_PER_M
    l, t, r, b = extra
    xmin -= (margin_px + l) / s
    xmax += (margin_px + r) / s
    ymin -= (margin_px + b) / s
    ymax += (margin_px + t) / s
    res_x = int(math.ceil((xmax - xmin) * s))
    res_y = int(math.ceil((ymax - ymin) * s))
    xmax = xmin + res_x / s
    ymax = ymin + res_y / s
    center = Vector(((xmin + xmax) / 2, (ymin + ymax) / 2, 60.0))
    cam.location = rot @ center
    cam.data.ortho_scale = max(res_x, res_y) / s
    cam.data.clip_end = 400
    sc = bpy.context.scene
    sc.render.resolution_x = res_x * SUPERSAMPLE
    sc.render.resolution_y = res_y * SUPERSAMPLE
    sc.render.resolution_percentage = 100
    bpy.context.view_layer.update()
    return cam, (res_x, res_y)


def frame_top_down(tile_m, overscan=0.08):
    """Camera straight down over [0, tile_m]^2 with overscan on every side."""
    cam = _camera(Euler((0, 0, 0)))
    size = tile_m * (1 + 2 * overscan)
    cam.location = (tile_m / 2, tile_m / 2, 50.0)
    cam.data.ortho_scale = size
    cam.data.clip_end = 200
    return cam


def to_pixel(cam, point, res):
    """World point -> pixel in the final (downscaled) image."""
    sc = bpy.context.scene
    co = world_to_camera_view(sc, cam, Vector(point))
    return (co.x * res[0], (1.0 - co.y) * res[1])


def render(path, res=None, crop=None, shadow_alpha=1.0):
    """Renders and saves `path`, downscaling from SUPERSAMPLE.
    crop = (x0, y0, x1, y1) fractions of the rendered frame to keep.
    shadow_alpha < 1 lightens shadow-catcher shadows (pure black, partly
    transparent pixels) without touching the object itself."""
    sc = bpy.context.scene
    tmp = Path(bpy.app.tempdir or "/tmp") / "lantern_render.png"
    sc.render.filepath = str(tmp)
    bpy.ops.render.render(write_still=True)
    img = Image.open(tmp).convert("RGBA")
    if shadow_alpha < 1.0:
        a = np.asarray(img).astype(np.float32)
        shadow = (a[..., 3] < 254) & (a[..., :3].max(axis=2) < 6)
        a[..., 3] = np.where(shadow, a[..., 3] * shadow_alpha, a[..., 3])
        img = Image.fromarray(a.astype(np.uint8), "RGBA")
    if crop is not None:
        w, h = img.size
        img = img.crop((round(crop[0] * w), round(crop[1] * h), round(crop[2] * w), round(crop[3] * h)))
    if res is not None:
        img = img.resize(res, Image.LANCZOS)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    return img


def rng(seed):
    return random.Random(seed)
