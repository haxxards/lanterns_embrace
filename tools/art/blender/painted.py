"""A painted look for rendered art (style test, not yet used by the game).

Three things move a clean 3D render towards hand-painted fantasy art:

1. Materials that look handled: bright worn edges (Cycles' Bevel node compared
   with the true normal finds the edges), dark grime in crevices (Ambient
   Occlusion), a light-to-dark gradient from top to bottom like a painter's
   lighting, and broad colour variation. See `metal`, `wood`, `leather`,
   `cloth`, `chain`, `glass`, `glow`.
2. A studio rig with a warm key, a cool rim and a soft fill (`studio`).
3. A finishing pass on the rendered image (`finish_painted`): a generalised
   Kuwahara filter (flat, brushy patches that keep edges sharp, as in an oil
   painting), a little more colour, and a dark outline.
"""
import math

import bpy
import numpy as np
from mathutils import Vector
from PIL import Image, ImageFilter
from scipy.signal import fftconvolve

import lib


# --------------------------------------------------------------------------
# Node helpers
# --------------------------------------------------------------------------

def _nodes(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    return mat, nt, nt.nodes["Principled BSDF"]


def _rgb(nt, hex_color):
    n = nt.nodes.new("ShaderNodeRGB")
    n.outputs[0].default_value = (*lib.lin(hex_color), 1.0)
    return n.outputs[0]


def _mix(nt, a, b, fac, blend='MIX'):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = 'RGBA'
    m.blend_type = blend
    _link(nt, fac, lib.sock(m.inputs, "Factor_Float"))
    _link(nt, a, lib.sock(m.inputs, "A_Color"))
    _link(nt, b, lib.sock(m.inputs, "B_Color"))
    return lib.sock(m.outputs, "Result_Color")


def _link(nt, src, dst):
    if isinstance(src, (int, float)):
        dst.default_value = src
    else:
        nt.links.new(src, dst)


def _math(nt, op, a, b=None, clamp=False):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = op
    m.use_clamp = clamp
    _link(nt, a, m.inputs[0])
    if b is not None:
        _link(nt, b, m.inputs[1])
    return m.outputs[0]


def _map(nt, value, a, b, c=0.0, d=1.0):
    m = nt.nodes.new("ShaderNodeMapRange")
    m.clamp = True
    _link(nt, value, m.inputs["Value"])
    m.inputs["From Min"].default_value = a
    m.inputs["From Max"].default_value = b
    m.inputs["To Min"].default_value = c
    m.inputs["To Max"].default_value = d
    return m.outputs["Result"]


def _noise(nt, scale, detail=4.0, coords="Object"):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    nt.links.new(tc.outputs[coords], n.inputs["Vector"])
    return n.outputs["Fac"]


def edge_mask(nt, radius=0.006, lo=0.02, hi=0.22, chip=0.55):
    """1 on worn edges, 0 elsewhere: where the bevelled normal leans away from
    the true one. Broken up with noise so the wear looks chipped, not drawn."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = radius
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    edge = _map(nt, _math(nt, 'SUBTRACT', 1.0, dot.outputs["Value"]), lo, hi)
    if chip > 0:
        ragged = _map(nt, _noise(nt, 38.0, 6.0), 0.5 - chip * 0.5, 0.5 + chip * 0.2)
        edge = _math(nt, 'MULTIPLY', edge, ragged, clamp=True)
    return edge


def cavity(nt, distance=0.04):
    """1 in the open, falling towards 0 in creases and where parts meet."""
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.only_local = False
    ao.inputs["Distance"].default_value = distance
    return ao.outputs["AO"]


def height_gradient(nt, lo=0.78, hi=1.12):
    """Brighter at the top of the object, darker at the bottom (painted light)."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    return _map(nt, sep.outputs["Z"], 0.0, 1.0, lo, hi)


def _painted(name, base, dark, edge_col, rough, metallic, edge_strength=1.0, grime=0.85,
             base_fn=None, ao_dist=0.04, bevel=0.006, chip=0.55, grad=(0.78, 1.12), var=0.12):
    """The common recipe: base colour (or `base_fn(nt)`, a pattern built in this
    material's node tree) with broad variation and a top-down gradient, grime
    in the crevices, wear on the edges."""
    mat, nt, bsdf = _nodes(name)
    col = base_fn(nt) if base_fn is not None else _rgb(nt, base)
    # Broad, soft colour variation, like uneven paint, and smaller smudges.
    v = _map(nt, _noise(nt, 3.0, 2.0), 0.0, 1.0, 1.0 - var, 1.0 + var)
    col = _mix(nt, col, _value_rgb(nt, v), 1.0, 'MULTIPLY')
    sm = _map(nt, _noise(nt, 14.0, 5.0), 0.25, 0.75, 1.0 - var * 0.8, 1.0 + var * 0.5)
    col = _mix(nt, col, _value_rgb(nt, sm), 1.0, 'MULTIPLY')
    col = _mix(nt, col, _value_rgb(nt, height_gradient(nt, *grad)), 1.0, 'MULTIPLY')
    # Grime in the creases.
    cav = cavity(nt, ao_dist)
    col = _mix(nt, _rgb(nt, dark), col, _map(nt, cav, 0.0, 1.0, 1.0 - grime, 1.0))
    # Worn, bright edges.
    e = edge_mask(nt, bevel, chip=chip)
    col = _mix(nt, col, _rgb(nt, edge_col), _math(nt, 'MULTIPLY', e, edge_strength, clamp=True))
    nt.links.new(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = metallic
    r = _mix_value(nt, rough, max(0.12, rough - 0.25), e)
    nt.links.new(r, bsdf.inputs["Roughness"])
    return mat, nt, bsdf


def _value_rgb(nt, v):
    c = nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        _link(nt, v, c.inputs[i])
    return c.outputs[0]


def _mix_value(nt, a, b, fac):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = 'FLOAT'
    _link(nt, fac, lib.sock(m.inputs, "Factor_Float"))
    _link(nt, a, lib.sock(m.inputs, "A_Float"))
    _link(nt, b, lib.sock(m.inputs, "B_Float"))
    return lib.sock(m.outputs, "Result_Float")


def _shade(hex_color, f, warm=0.0):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    r, g, b = min(1, r * f + warm), min(1, g * f + warm * 0.6), min(1, b * f)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

def metal(name, color="#8f959d", edge="#f2ede0", rough=0.42, metallic=0.8, scratches=True):
    mat, nt, bsdf = _painted(name, color, _shade(color, 0.25), edge, rough, metallic, edge_strength=1.0,
                             grime=0.85, var=0.2)
    if scratches:  # fine directional scratches in the roughness
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (2.0, 60.0, 2.0)
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = 6.0
        n.inputs["Detail"].default_value = 8.0
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.12
        nt.links.new(n.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def gold(name="Gold"):
    return metal(name, "#a8782e", edge="#ffe9a8", rough=0.36, metallic=0.9, scratches=False)


def iron(name="Iron"):
    return metal(name, "#6e6a66", edge="#d8d2c6", rough=0.5, metallic=0.75)


def wood(name, color="#7a4f2c", grain_scale=6.0, along="X"):
    """Planed wood: wave-texture grain along one axis (`along`), dark grooves,
    pale worn edges."""
    stretch = {"X": (0.15, 1.0, 1.0), "Y": (1.0, 0.15, 1.0), "Z": (1.0, 1.0, 0.15)}[along]
    holder = {}

    def grain(nt):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = 'BANDS'
        wave.bands_direction = 'Y' if along == "X" else 'X'
        wave.inputs["Scale"].default_value = grain_scale
        wave.inputs["Distortion"].default_value = 6.0
        wave.inputs["Detail"].default_value = 3.0
        nt.links.new(mp.outputs["Vector"], wave.inputs["Vector"])
        holder["wave"] = wave.outputs["Fac"]
        return _mix(nt, _rgb(nt, _shade(color, 0.7)), _rgb(nt, _shade(color, 1.2, 0.03)), wave.outputs["Fac"])

    mat, nt, bsdf = _painted(name, color, _shade(color, 0.3), _shade(color, 1.6, 0.08), 0.75, 0.0,
                             edge_strength=0.7, grime=0.9, chip=0.3, base_fn=grain)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(holder["wave"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _tint_base(nt, bsdf, factor):
    """Multiplies whatever feeds Base Color by a scalar socket."""
    link = bsdf.inputs["Base Color"].links[0]
    src = link.from_socket
    nt.links.remove(link)
    nt.links.new(_mix(nt, src, _value_rgb(nt, factor), 1.0, 'MULTIPLY'), bsdf.inputs["Base Color"])


def leather(name, color="#6b4227"):
    mat, nt, bsdf = _painted(name, color, _shade(color, 0.3), _shade(color, 1.55, 0.06), 0.62, 0.0,
                             edge_strength=0.8, grime=0.9, chip=0.4, var=0.2)
    _tint_base(nt, bsdf, _map(nt, _noise(nt, 22.0, 6.0), 0.3, 0.7, 0.85, 1.08))
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.3
    nt.links.new(_noise(nt, 60.0, 8.0), bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def cloth(name, color="#8e2a24", weave=180.0):
    mat, nt, bsdf = _painted(name, color, _shade(color, 0.35), _shade(color, 1.35, 0.05), 0.9, 0.0,
                             edge_strength=0.35, grime=0.85, chip=0.2, var=0.16)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    waves = []
    for axis in ('X', 'Y'):
        w = nt.nodes.new("ShaderNodeTexWave")
        w.bands_direction = axis
        w.inputs["Scale"].default_value = weave
        nt.links.new(tc.outputs["Object"], w.inputs["Vector"])
        waves.append(w.outputs["Fac"])
    weave_v = _math(nt, 'MULTIPLY', waves[0], waves[1])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    nt.links.new(weave_v, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def skin(name, color="#c99a74"):
    mat, nt, bsdf = _painted(name, color, _shade(color, 0.45, 0.02), _shade(color, 1.25, 0.05), 0.55, 0.0,
                             edge_strength=0.3, grime=0.7, chip=0.0, var=0.08)
    bsdf.inputs["Subsurface Weight"].default_value = 0.15
    return mat


def _ring_pattern(nt, scale):
    """Interlocking mail rings seen from the front: a staggered grid of
    circles in the object's X/Z plane. Returns 1 on the ring wire, 0 in gaps."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    x = _math(nt, 'MULTIPLY', sep.outputs["X"], scale)
    z = _math(nt, 'MULTIPLY', sep.outputs["Z"], scale * 1.15)
    row = _math(nt, 'FLOOR', z)
    shift = _math(nt, 'MULTIPLY', _math(nt, 'FLOORED_MODULO', row, 2.0), 0.5)
    fx = _math(nt, 'SUBTRACT', _math(nt, 'FRACT', _math(nt, 'ADD', x, shift)), 0.5)
    fz = _math(nt, 'SUBTRACT', _math(nt, 'FRACT', z), 0.5)
    d = _math(nt, 'SQRT', _math(nt, 'ADD', _math(nt, 'MULTIPLY', fx, fx), _math(nt, 'MULTIPLY', fz, fz)))
    band = _math(nt, 'ABSOLUTE', _math(nt, 'SUBTRACT', d, 0.36))
    return _map(nt, band, 0.16, 0.02, 0.0, 1.0)


def chain(name="Mail", color="#8a8f96", rings=55.0):
    """Riveted mail: interlocking rings with dark gaps between them, bright
    tops, and grime in the folds."""
    holder = {}

    def base(nt):
        ring = _ring_pattern(nt, rings)
        holder["ring"] = ring
        return _mix(nt, _rgb(nt, "#262523"), _rgb(nt, color), ring)

    mat, nt, bsdf = _painted(name, color, "#1c1b19", "#f0ece2", 0.4, 0.65, edge_strength=0.5, grime=0.7,
                             chip=0.3, base_fn=base, var=0.18)
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.8
    nt.links.new(holder["ring"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def glass(name="Glass", tint="#e8f0ee"):
    mat, nt, bsdf = _nodes(name)
    bsdf.inputs["Base Color"].default_value = (*lib.lin(tint), 1.0)
    bsdf.inputs["Roughness"].default_value = 0.03
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["IOR"].default_value = 1.35
    bsdf.inputs["Coat Weight"].default_value = 0.5
    return mat


def glow(name, color, strength=3.0, core="#fff2c8"):
    """A liquid or gem lit from inside: brighter at its heart (object centre)."""
    mat, nt, bsdf = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = 'SPHERICAL'
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (9.0, 9.0, 9.0)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
    col = _mix(nt, _rgb(nt, color), _rgb(nt, core), _map(nt, grad.outputs["Fac"], 0.2, 1.0, 0.0, 0.7))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(col, bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.08
    bsdf.inputs["Coat Weight"].default_value = 1.0
    return mat


# --------------------------------------------------------------------------
# Lighting
# --------------------------------------------------------------------------

def studio(key=520.0, rim=520.0, fill=150.0):
    """Warm key from the upper left, cool rim from behind right, soft warm fill."""
    for name, loc, energy, color, size in (
            ("Key", (-3.0, -3.5, 5.0), key, (1.0, 0.92, 0.78), 2.0),
            ("Fill", (4.0, -2.5, 1.5), fill, (1.0, 0.8, 0.62), 3.0),
            ("Rim", (2.5, 4.0, 3.0), rim, (0.62, 0.78, 1.0), 1.5),
            ("Top", (0.0, 0.5, 6.0), key * 0.2, (1.0, 0.96, 0.9), 4.0)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy
        data.color = color
        data.size = size
        obj = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(obj)
        obj.location = loc
        obj.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    # A film-like response rolls highlights off softly instead of clipping to white.
    vs = bpy.context.scene.view_settings
    vs.view_transform = 'AgX'
    vs.look = 'AgX - Punchy'



# --------------------------------------------------------------------------
# Finishing pass
# --------------------------------------------------------------------------

def kuwahara(rgb, alpha, radius=5, sectors=8, q=6.0):
    """Generalised Kuwahara filter (Papari et al.): each pixel takes the mean
    of the least varied of eight soft pie slices around it, so flat areas
    become brush-like patches while edges stay sharp. Alpha-weighted so the
    transparent background doesn't bleed in."""
    r = radius
    y, x = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float64)
    ang = np.arctan2(y, x)
    dist = np.hypot(x, y)
    gauss = np.exp(-(dist ** 2) / (2 * (r / 2.0) ** 2)) * (dist <= r + 0.5)
    w = alpha.astype(np.float64)
    num = np.zeros(rgb.shape, np.float64)
    den = np.zeros(rgb.shape[:2], np.float64)
    for k in range(sectors):
        mid = -math.pi + (k + 0.5) * 2 * math.pi / sectors
        d = np.angle(np.exp(1j * (ang - mid)))
        mask = np.exp(-(d ** 2) / (2 * (math.pi / sectors) ** 2)) * gauss
        mask[r, r] = gauss[r, r]
        mask /= mask.sum()
        sw = fftconvolve(w, mask, mode='same') + 1e-6
        m = np.stack([fftconvolve(rgb[..., c] * w, mask, mode='same') for c in range(3)], -1) / sw[..., None]
        s2 = np.stack([fftconvolve(rgb[..., c] ** 2 * w, mask, mode='same') for c in range(3)], -1) / sw[..., None]
        sigma = np.sqrt(np.clip(s2 - m ** 2, 0, None)).sum(-1)
        wk = 1.0 / (1e-4 + sigma) ** q
        num += wk[..., None] * m
        den += wk
    return np.clip(num / den[..., None], 0, 1)


def finish_painted(img, radius=5, outline_px=3, outline="#1a120c", saturation=1.12, contrast=1.06):
    """Turns a straight-alpha RGBA render into the painted look: Kuwahara
    brushwork, a touch more colour and contrast, and a dark outline."""
    a = np.asarray(img.convert("RGBA")).astype(np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    out = kuwahara(rgb, alpha, radius) if radius > 0 else rgb
    lum = out @ np.array([0.299, 0.587, 0.114])
    out = lum[..., None] + (out - lum[..., None]) * saturation
    out = (out - 0.5) * contrast + 0.5
    out = np.clip(out, 0, 1)
    body = Image.fromarray((np.dstack([out, alpha]) * 255).astype(np.uint8), "RGBA")
    if outline_px <= 0:
        return body
    a_img = Image.fromarray((alpha * 255).astype(np.uint8))
    ring = a_img.filter(ImageFilter.MaxFilter(outline_px * 2 + 1)).filter(ImageFilter.GaussianBlur(outline_px * 0.35))
    col = tuple(int(outline[i:i + 2], 16) for i in (1, 3, 5))
    line = Image.new("RGBA", body.size, (*col, 0))
    line.putalpha(ring.point(lambda v: int(v * 0.92)))
    res = Image.new("RGBA", body.size, (0, 0, 0, 0))
    res.alpha_composite(line)
    res.alpha_composite(body)
    return res
