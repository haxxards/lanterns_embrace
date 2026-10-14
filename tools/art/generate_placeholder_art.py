#!/usr/bin/env python3
"""Generates the placeholder art used by Lantern's Embrace.

Every PNG written here is a stand-in. Replace any file with real art (same
path, or point the data JSON at a new path) and the game picks it up. Sizes
and pivot points are listed in docs/ASSETS.md.

Requires Pillow and numpy:   pip install pillow numpy
Usage:
    python3 tools/art/generate_placeholder_art.py            # everything
    python3 tools/art/generate_placeholder_art.py --only terrain props
"""
import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
SS = 4  # supersampling factor for sprites
TEX = 256  # terrain texture size (seamless)


# --------------------------------------------------------------------------
# Generic helpers
# --------------------------------------------------------------------------

def rgba(hex_str, a=255):
    h = hex_str.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def rgb(hex_str):
    return rgba(hex_str)[:3]


def shade(hex_str, f, a=255):
    """Multiply a colour by f (<1 darker, >1 lighter)."""
    r, g, b, _ = rgba(hex_str)
    c = [max(0, min(255, int(v * f))) for v in (r, g, b)]
    return (c[0], c[1], c[2], a)


def tile_noise(n, seed, beta=2.0, aniso=(1.0, 1.0)):
    """Seamlessly tiling noise via random-phase spectrum (1/f^beta)."""
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


def to01(v, spread=0.2):
    return np.clip(0.5 + v * spread, 0.0, 1.0)


def colorize(v, stops):
    v = np.clip(v, 0, 1)
    pos = np.array([s[0] for s in stops])
    cols = np.array([rgb(s[1]) for s in stops], dtype=float)
    out = np.zeros(v.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(v, pos, cols[:, c])
    return out


def arr_to_img(a):
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def wrapped(n, x, y, margin):
    """Offsets needed to draw something at (x, y) seamlessly on an n-tile."""
    xs = [0] + ([n] if x < margin else []) + ([-n] if x > n - margin else [])
    ys = [0] + ([n] if y < margin else []) + ([-n] if y > n - margin else [])
    return [(ox, oy) for ox in xs for oy in ys]


def voronoi(n, count, seed):
    """Tileable Voronoi: returns (f1, f2, cell_index) arrays."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, n, (count, 2))
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    f1 = np.full((n, n), 1e9)
    f2 = np.full((n, n), 1e9)
    idx = np.zeros((n, n), dtype=int)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, n - dx)
        dy = np.abs(yy - py)
        dy = np.minimum(dy, n - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        idx = np.where(closer, i, idx)
        f1 = np.where(closer, d, f1)
    return f1, f2, idx


# --------------------------------------------------------------------------
# Terrain textures (seamless 256x256, drawn at 2x then downsampled)
# --------------------------------------------------------------------------

def tex_grass(seed=1, dark=False):
    n = TEX * 2
    v = 0.7 * to01(tile_noise(n, seed, 2.8), 0.22) + 0.3 * to01(tile_noise(n, seed + 1, 1.0), 0.2)
    if dark:
        stops = [(0, "#1f3517"), (0.45, "#2f4a20"), (0.75, "#3b5a27"), (1, "#4d6e31")]
    else:
        stops = [(0, "#36531f"), (0.45, "#4c7030"), (0.75, "#5d8538"), (1, "#759c47")]
    base = arr_to_img(colorize(v, stops)).convert("RGBA")
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    rng = np.random.default_rng(seed + 7)
    blade_cols = (["#253d18", "#3e5f28", "#5b7f36"] if dark
                  else ["#3a5a22", "#6c9542", "#86ad55", "#4a6c2b"])
    for _ in range(n * n // 70):
        x, y = rng.uniform(0, n, 2)
        ang = math.radians(-90 + rng.uniform(-28, 28))
        ln = rng.uniform(5, 13)
        col = rgba(blade_cols[rng.integers(len(blade_cols))], int(rng.uniform(90, 190)))
        for ox, oy in wrapped(n, x, y, 16):
            d.line([(x + ox, y + oy), (x + ox + math.cos(ang) * ln, y + oy + math.sin(ang) * ln)],
                   fill=col, width=2)
    if dark:
        for _ in range(90):  # leaf litter
            x, y = rng.uniform(0, n, 2)
            col = rgba(["#5a4326", "#6e5530", "#4a3a22"][rng.integers(3)], 200)
            r = rng.uniform(2, 4)
            for ox, oy in wrapped(n, x, y, 8):
                d.ellipse([x + ox - r, y + oy - r * 0.6, x + ox + r, y + oy + r * 0.6], fill=col)
    else:
        for _ in range(26):  # tiny flowers
            x, y = rng.uniform(0, n, 2)
            col = rgba(["#e8e2c0", "#e6cf5a", "#c8a6d8"][rng.integers(3)], 230)
            for ox, oy in wrapped(n, x, y, 8):
                d.ellipse([x + ox - 2, y + oy - 2, x + ox + 2, y + oy + 2], fill=col)
    base.alpha_composite(layer)
    return base.convert("RGB").resize((TEX, TEX), Image.LANCZOS)


def tex_dirt(seed=11):
    n = TEX * 2
    v = 0.65 * to01(tile_noise(n, seed, 2.6), 0.2) + 0.35 * to01(tile_noise(n, seed + 1, 0.8), 0.2)
    base = arr_to_img(colorize(v, [(0, "#4f3d29"), (0.5, "#6f573b"), (1, "#8d7350")])).convert("RGBA")
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    rng = np.random.default_rng(seed + 3)
    for _ in range(170):
        x, y = rng.uniform(0, n, 2)
        r = rng.uniform(2.5, 6.5)
        c = ["#7b746a", "#8c8274", "#5f5649", "#9a8c76"][rng.integers(4)]
        for ox, oy in wrapped(n, x, y, 12):
            cx, cy = x + ox, y + oy
            d.ellipse([cx - r, cy - r * 0.75, cx + r, cy + r * 0.75], fill=rgba(c, 235))
            d.ellipse([cx - r * 0.5, cy - r * 0.6, cx + r * 0.1, cy - r * 0.1], fill=shade(c, 1.25, 160))
            d.arc([cx - r, cy - r * 0.75, cx + r, cy + r * 0.75], 20, 160, fill=rgba("#2f2418", 150), width=2)
    base.alpha_composite(layer)
    return base.convert("RGB").resize((TEX, TEX), Image.LANCZOS)


def tex_sand(seed=21):
    n = TEX * 2
    v = 0.7 * to01(tile_noise(n, seed, 2.4), 0.2) + 0.3 * to01(tile_noise(n, seed + 1, 0.4), 0.25)
    a = colorize(v, [(0, "#a88f60"), (0.5, "#c4ab78"), (1, "#dcc796")])
    rng = np.random.default_rng(seed + 2)
    speck = rng.random((n, n))
    a[speck > 0.985] *= 0.75
    a[speck < 0.012] *= 1.12
    return arr_to_img(a).resize((TEX, TEX), Image.LANCZOS)


def water_waves(n, seed):
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    warp = tile_noise(n, seed + 5, 3.0)
    phase = 2 * np.pi * (2 * xx + 5 * yy) / n + 1.6 * warp
    w = np.sin(phase)
    mod = to01(tile_noise(n, seed + 6, 2.0), 0.35)
    return smoothstep(0.86, 0.985, w) * mod


def tex_water(seed=31):
    n = TEX * 2
    v = to01(tile_noise(n, seed, 2.6), 0.22)
    a = colorize(v, [(0, "#1c3a58"), (0.5, "#28547a"), (1, "#3a719c")])
    hl = water_waves(n, seed)[..., None]
    a = a * (1 - 0.6 * hl) + np.array(rgb("#a9d6ee")) * 0.6 * hl
    return arr_to_img(a).resize((TEX, TEX), Image.LANCZOS)


def tex_shallows(seed=41):
    n = TEX * 2
    v = 0.7 * to01(tile_noise(n, seed, 2.4), 0.22) + 0.3 * to01(tile_noise(n, seed + 1, 0.8), 0.2)
    bottom = colorize(v, [(0, "#6f6a4e"), (0.5, "#8a8460"), (1, "#a39c72")])
    tint = np.array(rgb("#3f8aa6"))
    a = bottom * 0.45 + tint * 0.55
    hl = water_waves(n, seed)[..., None]
    a = a * (1 - 0.55 * hl) + np.array(rgb("#c9eaf5")) * 0.55 * hl
    return arr_to_img(a).resize((TEX, TEX), Image.LANCZOS)


def tex_cobble(seed=51):
    n = TEX * 2
    f1, f2, idx = voronoi(n, 95, seed)
    rng = np.random.default_rng(seed + 1)
    tones = rng.uniform(0.8, 1.15, idx.max() + 1)
    noise = to01(tile_noise(n, seed + 2, 1.4), 0.2)
    base = colorize(noise, [(0, "#6a665f"), (0.5, "#85807a"), (1, "#a29d94")])
    base *= tones[idx][..., None]
    edge = f2 - f1
    bevel = smoothstep(0, 14, edge)[..., None]
    base = base * (0.72 + 0.28 * bevel)
    mortar = smoothstep(5, 2, edge)[..., None]
    base = base * (1 - mortar) + np.array(rgb("#3d3a35")) * mortar
    return arr_to_img(base).resize((TEX, TEX), Image.LANCZOS)


def tex_planks(seed=61, vertical=True):
    n = TEX * 2
    plank_w = 64
    grain = to01(tile_noise(n, seed, 1.8, aniso=(1.0, 8.0) if vertical else (8.0, 1.0)), 0.3)
    yy, xx = np.mgrid[0:n, 0:n]
    across = xx if vertical else yy
    along = yy if vertical else xx
    plank = across // plank_w
    rng = np.random.default_rng(seed + 1)
    tones = rng.uniform(0.82, 1.12, n // plank_w + 1)
    a = colorize(grain, [(0, "#5a3d22"), (0.5, "#7a5634"), (1, "#9a7048")])
    a *= tones[plank][..., None]
    gap = (across % plank_w) < 4
    a[gap] = np.array(rgb("#2a1c10"))
    seams = rng.integers(0, n, n // plank_w + 1)
    seam = (np.abs(along - seams[plank]) < 3) & ~gap
    a[seam] = np.array(rgb("#33230f"))
    img = arr_to_img(a).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    for p in range(n // plank_w):
        c = p * plank_w + plank_w // 2
        s = seams[p]
        for off in (-10, 10):
            for k in (-14, 14):
                x, y = (c + k, s + off) if vertical else (s + off, c + k)
                d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=rgba("#1e1610", 220))
    return img.convert("RGB").resize((TEX, TEX), Image.LANCZOS)


def tex_rock(seed=71):
    n = TEX * 2
    f1, f2, idx = voronoi(n, 26, seed)
    rng = np.random.default_rng(seed + 1)
    tones = rng.uniform(0.85, 1.12, idx.max() + 1)
    noise = 0.6 * to01(tile_noise(n, seed + 2, 2.2), 0.25) + 0.4 * to01(tile_noise(n, seed + 3, 0.9), 0.25)
    a = colorize(noise, [(0, "#3e3d40"), (0.5, "#5f5e62"), (1, "#86858a")])
    a *= tones[idx][..., None]
    # light from the top-left: brighten cell areas near their upper-left edge
    gy, gx = np.gradient(f1)
    lit = np.clip(-(gx + gy) * 0.6, -0.25, 0.25)[..., None]
    a = a * (1 + lit)
    crack = smoothstep(3.5, 1.0, f2 - f1)[..., None]
    a = a * (1 - crack) + np.array(rgb("#1f1e21")) * crack
    return arr_to_img(a).resize((TEX, TEX), Image.LANCZOS)


TERRAIN = {
    "grass": lambda: tex_grass(1),
    "grass_dark": lambda: tex_grass(2, dark=True),
    "dirt_road": tex_dirt,
    "sand": tex_sand,
    "water": tex_water,
    "shallows": tex_shallows,
    "cobblestone": tex_cobble,
    "bridge_planks": lambda: tex_planks(61, vertical=True),
    "rock": tex_rock,
}


# --------------------------------------------------------------------------
# Sprite canvas helper (drawn at SSx and downsampled for anti-aliasing)
# --------------------------------------------------------------------------

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))

    def layer(self):
        return Image.new("RGBA", self.img.size, (0, 0, 0, 0))

    @staticmethod
    def draw(im):
        return ImageDraw.Draw(im, "RGBA")

    @staticmethod
    def pts(points):
        return [(x * SS, y * SS) for x, y in points]

    def ellipse(self, im, cx, cy, rx, ry, fill, outline=None, width=0):
        self.draw(im).ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS],
                              fill=fill, outline=outline, width=int(width * SS))

    def poly(self, im, points, fill, outline=None, width=0):
        self.draw(im).polygon(self.pts(points), fill=fill, outline=outline, width=int(width * SS))

    def line(self, im, points, fill, width=1.0):
        self.draw(im).line(self.pts(points), fill=fill, width=max(1, int(width * SS)), joint="curve")

    def rect(self, im, x0, y0, x1, y1, fill, outline=None, width=0, radius=0):
        self.draw(im).rounded_rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=radius * SS,
                                        fill=fill, outline=outline, width=int(width * SS))

    def comp(self, layer, clip=None):
        """Composite `layer` onto the canvas, optionally clipped to `clip`'s alpha."""
        if clip is not None:
            a = ImageChops.multiply(layer.getchannel("A"), clip.getchannel("A"))
            layer = layer.copy()
            layer.putalpha(a)
        self.img.alpha_composite(layer)

    def outline(self, color, px=1.0):
        """Adds a solid outline around everything drawn so far."""
        a = self.img.getchannel("A").point(lambda v: 255 if v > 40 else 0)
        k = int(px * SS) * 2 + 1
        dil = a.filter(ImageFilter.MaxFilter(k))
        out = Image.new("RGBA", self.img.size, color)
        out.putalpha(dil)
        out.alpha_composite(self.img)
        self.img = out

    def shadow(self, cx, cy, rx, ry, alpha=80):
        lay = self.layer()
        self.ellipse(lay, cx, cy, rx, ry, (0, 0, 0, alpha))
        lay = lay.filter(ImageFilter.GaussianBlur(2 * SS))
        under = lay
        under.alpha_composite(self.img)
        self.img = under

    def save(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.img.resize((self.w, self.h), Image.LANCZOS).save(path)


def blob_layers(c, circles, base, mid, light, dark_outline):
    """Leafy blob made of circles with three-tone shading clipped to its shape."""
    body = c.layer()
    for (x, y, r) in circles:
        c.ellipse(body, x, y, r, r, rgba(base))
    mid_l = c.layer()
    for (x, y, r) in circles:
        c.ellipse(mid_l, x - r * 0.18, y - r * 0.22, r * 0.82, r * 0.8, rgba(mid))
    light_l = c.layer()
    for (x, y, r) in circles:
        c.ellipse(light_l, x - r * 0.35, y - r * 0.42, r * 0.45, r * 0.4, rgba(light, 210))
    tmp = Canvas(c.w, c.h)
    tmp.img = body.copy()
    tmp.comp(mid_l, clip=body)
    tmp.comp(light_l, clip=body)
    tmp.outline(rgba(dark_outline), 1.0)
    return tmp.img


# --------------------------------------------------------------------------
# Props
# --------------------------------------------------------------------------

def prop_tree_oak():
    c = Canvas(112, 128)
    trunk = c.layer()
    c.poly(trunk, [(49, 116), (63, 116), (61, 84), (52, 84)], rgba("#5b3f26"))
    c.poly(trunk, [(57, 116), (63, 116), (61, 84), (57, 84)], rgba("#46301c"))
    c.poly(trunk, [(45, 117), (51, 112), (49, 118)], rgba("#5b3f26"))
    c.comp(trunk)
    circles = [(56, 34, 22), (35, 50, 19), (77, 50, 19), (44, 70, 19), (69, 70, 19),
               (56, 54, 23), (26, 66, 13), (86, 66, 13), (56, 78, 16)]
    canopy = blob_layers(c, circles, "#2a5021", "#3c6e2e", "#5f9645", "#13260f")
    c.img.alpha_composite(canopy)
    leaves = c.layer()
    rng = np.random.default_rng(5)
    for _ in range(40):
        x, y = rng.uniform(22, 90), rng.uniform(16, 84)
        c.ellipse(leaves, x, y, 1.6, 1.2, rgba(["#7cb35a", "#4f8a3a", "#1f3d19"][rng.integers(3)], 200))
    c.comp(leaves, clip=canopy)
    c.shadow(58, 116, 30, 8, 90)
    return c, (56, 116)


def prop_tree_pine():
    c = Canvas(88, 136)
    trunk = c.layer()
    c.rect(trunk, 40, 104, 48, 126, rgba("#4f3520"))
    c.rect(trunk, 44, 104, 48, 126, rgba("#3c2817"))
    c.comp(trunk)
    tiers = [(44, 112, 38, 34), (44, 88, 32, 32), (44, 64, 25, 30), (44, 42, 17, 28)]
    body = c.layer()
    for (cx, by, hw, h) in tiers:
        pts = [(cx, by - h - 6)]
        steps = 6
        for i in range(steps + 1):
            x = cx + hw - (2 * hw) * i / steps
            y = by + (3 if i % 2 == 0 else -3)
            pts.insert(1 + i, (x, y))
        c.poly(body, pts, rgba("#1c4630"))
    light = c.layer()
    for (cx, by, hw, h) in tiers:
        c.poly(light, [(cx - 1, by - h - 4), (cx - hw * 0.85, by - 1), (cx - hw * 0.15, by - 4)],
               rgba("#2f6b48"))
        c.poly(light, [(cx - 3, by - h + 4), (cx - hw * 0.55, by - 6), (cx - hw * 0.3, by - 8)],
               rgba("#4d8f63", 200))
    tmp = Canvas(c.w, c.h)
    tmp.img = body.copy()
    tmp.comp(light, clip=body)
    tmp.outline(rgba("#0c2017"), 1.0)
    c.img.alpha_composite(tmp.img)
    c.shadow(46, 126, 26, 7, 90)
    return c, (44, 126)


def prop_bush():
    c = Canvas(64, 48)
    circles = [(22, 28, 12), (40, 26, 13), (31, 18, 11), (14, 34, 8), (50, 34, 8), (31, 32, 12)]
    c.img.alpha_composite(blob_layers(c, circles, "#2d5424", "#41763a", "#66a04c", "#132611"))
    berries = c.layer()
    rng = np.random.default_rng(9)
    for _ in range(7):
        x, y = rng.uniform(14, 50), rng.uniform(16, 38)
        c.ellipse(berries, x, y, 1.6, 1.6, rgba("#b8323a"))
    c.comp(berries)
    c.shadow(32, 41, 24, 5, 80)
    return c, (32, 40)


def prop_rock():
    c = Canvas(60, 46)
    body = c.layer()
    pts = [(8, 36), (12, 20), (24, 10), (40, 9), (52, 18), (55, 34), (44, 40), (20, 41)]
    c.poly(body, pts, rgba("#6c6b70"))
    top = c.layer()
    c.poly(top, [(13, 21), (24, 11), (40, 10), (50, 18), (38, 24), (22, 26)], rgba("#93929a"))
    side = c.layer()
    c.poly(side, [(38, 24), (50, 18), (55, 34), (44, 40), (36, 38)], rgba("#4e4d52"))
    tmp = Canvas(c.w, c.h)
    tmp.img = body.copy()
    tmp.comp(top, clip=body)
    tmp.comp(side, clip=body)
    tmp.line(tmp.img, [(24, 26), (28, 33), (26, 39)], rgba("#3b3a3e", 200), 1)
    tmp.outline(rgba("#242327"), 1.0)
    c.img.alpha_composite(tmp.img)
    c.shadow(32, 40, 26, 5, 80)
    return c, (31, 38)


def prop_sign():
    c = Canvas(48, 68)
    wood = c.layer()
    c.rect(wood, 22, 22, 27, 62, rgba("#5d4128"))
    c.rect(wood, 25, 22, 27, 62, rgba("#47311d"))
    c.rect(wood, 5, 10, 43, 32, rgba("#8a6a43"), radius=2)
    c.rect(wood, 5, 28, 43, 32, rgba("#6e5233"), radius=1)
    for i, w in enumerate((28, 22, 25)):
        y = 15 + i * 5
        c.line(wood, [(10, y), (10 + w, y)], rgba("#3a2a18", 220), 1.3)
    c.comp(wood)
    c.outline(rgba("#21170d"), 1.0)
    c.shadow(25, 62, 12, 3.5, 90)
    return c, (24, 62)


def prop_well():
    c = Canvas(80, 92)
    lay = c.layer()
    # posts and roof
    c.rect(lay, 14, 18, 19, 60, rgba("#5d4128"))
    c.rect(lay, 61, 18, 66, 60, rgba("#47311d"))
    c.line(lay, [(16, 34), (64, 34)], rgba("#4a3420"), 2.2)
    c.poly(lay, [(6, 22), (40, 4), (74, 22), (66, 26), (40, 12), (14, 26)], rgba("#7a3a2c"))
    c.poly(lay, [(40, 4), (74, 22), (66, 26), (40, 12)], rgba("#5f2c21"))
    # stone ring
    c.ellipse(lay, 40, 72, 30, 12, rgba("#6a676c"))
    c.rect(lay, 10, 56, 70, 72, rgba("#77747a"))
    c.ellipse(lay, 40, 56, 30, 12, rgba("#8f8c92"))
    c.ellipse(lay, 40, 56, 23, 8, rgba("#1d2a33"))
    c.ellipse(lay, 40, 57, 18, 5, rgba("#2c4656"))
    for x in (18, 30, 42, 54, 64):
        c.line(lay, [(x, 60), (x, 71)], rgba("#55525a"), 1)
    c.line(lay, [(11, 65), (69, 65)], rgba("#55525a"), 1)
    # rope + bucket
    c.line(lay, [(40, 34), (40, 46)], rgba("#c9b58a"), 1)
    c.rect(lay, 36, 46, 44, 52, rgba("#6e5233"))
    c.comp(lay)
    c.outline(rgba("#1d1914"), 1.0)
    c.shadow(42, 80, 34, 8, 80)
    return c, (40, 72)


def prop_house(width, roof_main, roof_dark, door_x, windows, chimney_x, footprint_bottom):
    """3/4 view timber-framed cottage. Returns (canvas, origin)."""
    w = width
    h = 248
    c = Canvas(w, h)
    wall_top, ground = 170, footprint_bottom
    lay = c.layer()
    # front wall
    c.rect(lay, 10, wall_top, w - 10, ground, rgba("#d9caa3"))
    c.rect(lay, 10, ground - 8, w - 10, ground, rgba("#8b867d"))
    for x in range(14, w - 14, 9):
        c.line(lay, [(x, ground - 8), (x, ground)], rgba("#6d6961"), 0.8)
    beam = rgba("#5a3d25")
    c.rect(lay, 10, wall_top, w - 10, wall_top + 5, beam)
    for x in [10, w - 16] + [wx + ww + 3 for wx, ww in windows]:
        c.rect(lay, x, wall_top, x + 6, ground - 8, beam)
    for wx, ww in windows:
        c.rect(lay, wx - 2, 182, wx + ww + 2, 204, beam)
        c.rect(lay, wx, 184, wx + ww, 202, rgba("#9cc2d6"))
        c.line(lay, [(wx + ww / 2, 184), (wx + ww / 2, 202)], beam, 1.4)
        c.line(lay, [(wx, 193), (wx + ww, 193)], beam, 1.4)
        c.rect(lay, wx - 6, 183, wx - 2, 203, rgba("#4f6b3a"))
        c.rect(lay, wx + ww + 2, 183, wx + ww + 6, 203, rgba("#4f6b3a"))
    # door
    c.rect(lay, door_x - 13, 186, door_x + 13, ground - 6, rgba("#3f2a18"), radius=9)
    c.rect(lay, door_x - 10, 189, door_x + 10, ground - 6, rgba("#6b4627"), radius=7)
    for dx in (-4, 4):
        c.line(lay, [(door_x + dx, 192), (door_x + dx, ground - 7)], rgba("#4f331d"), 1)
    c.ellipse(lay, door_x + 6, 210, 1.6, 1.6, rgba("#d8c070"))
    c.rect(lay, door_x - 15, ground - 7, door_x + 15, ground - 3, rgba("#77736b"))
    # roof: back slope, then front slope (overhanging eaves)
    ridge_y, back_y, eave_y = 96, 44, wall_top + 6
    c.poly(lay, [(14, ridge_y), (w - 14, ridge_y), (w - 22, back_y), (22, back_y)], rgba(roof_dark))
    if chimney_x is not None:
        c.rect(lay, chimney_x, 30, chimney_x + 16, 70, rgba("#7a6e66"))
        c.rect(lay, chimney_x - 2, 26, chimney_x + 18, 32, rgba("#5d544e"))
        for y in (40, 50, 60):
            c.line(lay, [(chimney_x, y), (chimney_x + 16, y)], rgba("#5d544e"), 1)
    c.poly(lay, [(4, eave_y), (w - 4, eave_y), (w - 14, ridge_y), (14, ridge_y)], rgba(roof_main))
    # shingle rows
    rows = 7
    for i in range(1, rows):
        t = i / rows
        y = ridge_y + (eave_y - ridge_y) * t
        x0 = 14 + (4 - 14) * t
        x1 = (w - 14) + ((w - 4) - (w - 14)) * t
        c.line(lay, [(x0, y), (x1, y)], shade(roof_main, 0.72), 1.4)
        step = 12
        off = 0 if i % 2 else step / 2
        x = x0 + off
        while x < x1 - 2:
            y_prev = ridge_y + (eave_y - ridge_y) * (i - 1) / rows
            c.line(lay, [(x, y_prev + 1), (x, y - 1)], shade(roof_main, 0.8), 0.9)
            x += step
    c.poly(lay, [(4, eave_y), (w - 4, eave_y), (w - 6, eave_y - 7), (6, eave_y - 7)],
           shade(roof_main, 1.12))
    c.line(lay, [(14, ridge_y), (w - 14, ridge_y)], shade(roof_dark, 0.7), 3)
    for i in range(1, 5):
        y = back_y + (ridge_y - back_y) * i / 5
        c.line(lay, [(22 - 8 * i / 5, y), (w - 22 + 8 * i / 5, y)], shade(roof_dark, 0.8), 1.2)
    c.comp(lay)
    c.outline(rgba("#1b140d"), 1.0)
    c.shadow(w / 2 + 6, ground - 2, w / 2 - 4, 10, 90)
    return c


def prop_house_small():
    # Footprint: anchor hex + its 6 neighbours. Origin = anchor hex centre.
    c = prop_house(184, "#9a4231", "#6e2d22", door_x=120, windows=[(32, 22), (62, 20), (146, 20)],
                   chimney_x=40, footprint_bottom=226)
    return c, (92, 160)


def prop_house_large():
    # Footprint: anchor + neighbours, and (1,0) + its neighbours. Origin = anchor hex centre.
    c = prop_house(248, "#4b5d73", "#33414f", door_x=180, windows=[(28, 22), (60, 22), (100, 22),
                                                                   (132, 22), (210, 22)],
                   chimney_x=196, footprint_bottom=226)
    return c, (97, 160)


PROPS = {
    "tree_oak": prop_tree_oak,
    "tree_pine": prop_tree_pine,
    "bush": prop_bush,
    "rock": prop_rock,
    "sign": prop_sign,
    "well": prop_well,
    "house_small": prop_house_small,
    "house_large": prop_house_large,
}


# --------------------------------------------------------------------------
# Characters (front-facing 48x64 sprites; feet at (24, 58))
# --------------------------------------------------------------------------

def char_base(c, skin, tunic, boots, arms_col, robe=False, robe_col=None):
    lay = c.layer()
    if robe:
        c.poly(lay, [(15, 30), (33, 30), (37, 58), (11, 58)], rgba(robe_col))
        c.poly(lay, [(24, 30), (33, 30), (37, 58), (25, 58)], shade(robe_col, 0.82))
    else:
        c.rect(lay, 17, 44, 22, 58, rgba(boots), radius=1)
        c.rect(lay, 26, 44, 31, 58, rgba(boots), radius=1)
        c.rect(lay, 16, 54, 22, 58, shade(boots, 0.7), radius=1)
        c.rect(lay, 26, 54, 32, 58, shade(boots, 0.7), radius=1)
    c.rect(lay, 9, 30, 15, 45, rgba(arms_col), radius=3)
    c.rect(lay, 33, 30, 39, 45, rgba(arms_col), radius=3)
    c.ellipse(lay, 12, 46, 3, 3, rgba(skin))
    c.ellipse(lay, 36, 46, 3, 3, rgba(skin))
    c.rect(lay, 14, 28, 34, 48, rgba(tunic), radius=4)
    c.rect(lay, 24, 28, 34, 48, shade(tunic, 0.85), radius=4)
    c.rect(lay, 21, 25, 27, 30, rgba(skin))
    c.ellipse(lay, 24, 18, 9, 9.5, rgba(skin))
    c.ellipse(lay, 29, 20, 3.5, 6.5, shade(skin, 0.88, 90))
    c.ellipse(lay, 20.5, 19, 1.3, 1.6, rgba("#1d1612"))
    c.ellipse(lay, 27.5, 19, 1.3, 1.6, rgba("#1d1612"))
    c.comp(lay)


def char_fighter():
    c = Canvas(48, 64)
    lay = c.layer()
    # shield (behind arm)
    c.ellipse(lay, 10, 38, 9, 10, rgba("#6b4a2b"))
    c.ellipse(lay, 10, 38, 9, 10, None, rgba("#b8b8c0"), 1.4)
    c.ellipse(lay, 10, 38, 3, 3, rgba("#c9a43a"))
    c.comp(lay)
    char_base(c, "#c99a74", "#8a96a8", "#3f3128", "#7a8698")
    lay = c.layer()
    c.rect(lay, 20, 29, 28, 48, rgba("#9b2c2c"))
    c.rect(lay, 14, 42, 34, 45, rgba("#4a3626"))
    c.ellipse(lay, 13, 31, 5, 4, rgba("#a3aebf"))
    c.ellipse(lay, 35, 31, 5, 4, rgba("#8592a6"))
    # hair
    c.poly(lay, [(15, 16), (17, 9), (24, 7), (31, 9), (33, 16), (30, 12), (24, 11), (18, 12)], rgba("#3b2617"))
    # sword
    c.line(lay, [(38, 46), (42, 10)], rgba("#d5d9e0"), 2.2)
    c.line(lay, [(39, 44), (42, 16)], rgba("#9aa1ad"), 0.8)
    c.line(lay, [(33, 43), (42, 44)], rgba("#7a5a2a"), 2.2)
    c.comp(lay)
    c.outline(rgba("#17120e"), 1.0)
    return c


def char_wizard():
    c = Canvas(48, 64)
    lay = c.layer()
    # staff behind
    c.line(lay, [(39, 58), (40, 10)], rgba("#6b4a2b"), 2.2)
    c.comp(lay)
    char_base(c, "#e2c3a5", "#5b3a8c", "#2a1f2f", "#5b3a8c", robe=True, robe_col="#5b3a8c")
    lay = c.layer()
    # long silver hair
    c.poly(lay, [(14, 18), (16, 10), (24, 8), (32, 10), (34, 18), (35, 32), (30, 30), (31, 18),
                 (17, 18), (18, 30), (13, 32)], rgba("#d9dde6"))
    c.poly(lay, [(14, 20), (12, 23), (15, 21)], rgba("#e2c3a5"))  # pointed ear
    c.poly(lay, [(34, 20), (36, 23), (33, 21)], rgba("#e2c3a5"))
    # hat
    c.ellipse(lay, 24, 11, 15, 3.5, rgba("#432a68"))
    c.poly(lay, [(15, 11), (33, 11), (28, -1), (36, -6), (24, 0)], rgba("#4f3279"))
    c.rect(lay, 16, 8, 32, 11, rgba("#c9a43a"))
    # belt and trim
    c.rect(lay, 15, 40, 33, 42, rgba("#c9a43a"))
    # orb
    glow = c.layer()
    c.ellipse(glow, 40, 9, 7, 7, rgba("#9fe8ff", 90))
    c.comp(glow)
    c.ellipse(lay, 40, 9, 3.4, 3.4, rgba("#c9f4ff"))
    c.comp(lay)
    c.outline(rgba("#17120e"), 1.0)
    return c


def char_cleric():
    c = Canvas(48, 64)
    char_base(c, "#8d5a3b", "#d9d2bf", "#4a3626", "#bdb49c", robe=True, robe_col="#d9d2bf")
    lay = c.layer()
    # gold trim + sun symbol
    c.rect(lay, 22, 30, 26, 56, rgba("#c9a43a"))
    c.ellipse(lay, 24, 36, 4, 4, rgba("#f0cf5a"))
    for i in range(8):
        a = i * math.pi / 4
        c.line(lay, [(24 + math.cos(a) * 4, 36 + math.sin(a) * 4),
                     (24 + math.cos(a) * 6.5, 36 + math.sin(a) * 6.5)], rgba("#f0cf5a"), 1)
    # bald head shine, big beard
    c.ellipse(lay, 21, 13, 3, 2, rgba("#a8714f"))
    c.poly(lay, [(15, 20), (33, 20), (31, 30), (27, 36), (24, 38), (21, 36), (17, 30)], rgba("#6a3f22"))
    c.poly(lay, [(19, 24), (29, 24), (24, 27)], rgba("#8d5a3b"))
    c.ellipse(lay, 20.5, 18.5, 1.3, 1.5, rgba("#1d1612"))
    c.ellipse(lay, 27.5, 18.5, 1.3, 1.5, rgba("#1d1612"))
    # mace
    c.line(lay, [(37, 48), (40, 26)], rgba("#5d4128"), 2)
    c.ellipse(lay, 40.5, 24, 4, 4, rgba("#9aa1ad"))
    for a in range(0, 360, 60):
        r = math.radians(a)
        c.ellipse(lay, 40.5 + math.cos(r) * 4, 24 + math.sin(r) * 4, 1.3, 1.3, rgba("#7a818c"))
    c.comp(lay)
    c.outline(rgba("#17120e"), 1.0)
    return c


def char_rogue():
    c = Canvas(48, 64)
    lay = c.layer()
    c.poly(lay, [(13, 27), (35, 27), (38, 52), (10, 52)], rgba("#24392d"))  # cloak behind
    c.comp(lay)
    char_base(c, "#d6a77f", "#5a4632", "#2a2019", "#4a3a2a")
    lay = c.layer()
    # hood
    c.ellipse(lay, 24, 17, 12, 12.5, rgba("#2f4a3a"))
    c.ellipse(lay, 24, 19, 8, 8.5, rgba("#d6a77f"))
    c.ellipse(lay, 24, 15, 8.5, 5, rgba("#1f3127", 200))
    c.rect(lay, 16, 21, 32, 27, rgba("#2a2722"), radius=2)  # scarf mask
    c.ellipse(lay, 20.5, 19, 1.3, 1.4, rgba("#1d1612"))
    c.ellipse(lay, 27.5, 19, 1.3, 1.4, rgba("#1d1612"))
    c.poly(lay, [(14, 26), (34, 26), (30, 32), (18, 32)], rgba("#2f4a3a"))
    c.rect(lay, 14, 40, 34, 42, rgba("#2a2019"))
    # daggers
    for hx, tip in ((12, (6, 54)), (36, (42, 54))):
        c.line(lay, [(hx, 47), tip], rgba("#d5d9e0"), 1.6)
        c.line(lay, [(hx - 3, 47), (hx + 3, 47)], rgba("#7a5a2a"), 1.5)
    c.comp(lay)
    c.outline(rgba("#17120e"), 1.0)
    return c


CHARACTERS = {
    "fighter": char_fighter,
    "wizard": char_wizard,
    "cleric": char_cleric,
    "rogue": char_rogue,
}


# --------------------------------------------------------------------------
# Portraits (128x160 busts)
# --------------------------------------------------------------------------

def portrait_bg(c, top, bottom):
    h = c.h * SS
    grad = np.linspace(0, 1, h)[:, None]
    a = np.array(rgb(top)) * (1 - grad[..., None]) + np.array(rgb(bottom)) * grad[..., None]
    a = np.repeat(a, c.w * SS, axis=1)
    yy, xx = np.mgrid[0:h, 0:c.w * SS]
    cx, cy = c.w * SS / 2, h * 0.42
    d = np.sqrt(((xx - cx) / (c.w * SS * 0.7)) ** 2 + ((yy - cy) / (h * 0.7)) ** 2)
    a = a * (1.15 - 0.55 * np.clip(d, 0, 1))[..., None]
    img = arr_to_img(a).convert("RGBA")
    c.img.alpha_composite(img)


def portrait_face(c, skin, eye="#2b2420", brow="#3a2a1d", ears=True, pointed=False):
    lay = c.layer()
    c.rect(lay, 52, 96, 76, 128, rgba(skin))
    c.rect(lay, 64, 96, 76, 128, shade(skin, 0.85))
    if ears:
        if pointed:
            c.poly(lay, [(40, 72), (28, 58), (42, 86)], rgba(skin))
            c.poly(lay, [(88, 72), (100, 58), (86, 86)], shade(skin, 0.88))
        else:
            c.ellipse(lay, 38, 76, 5, 8, rgba(skin))
            c.ellipse(lay, 90, 76, 5, 8, shade(skin, 0.88))
    c.ellipse(lay, 64, 72, 26, 32, rgba(skin))
    c.comp(lay)
    sh = c.layer()
    c.ellipse(sh, 78, 76, 16, 30, shade(skin, 0.82, 170))
    c.ellipse(sh, 64, 102, 20, 6, shade(skin, 0.8, 120))
    c.comp(sh, clip=lay)
    f = c.layer()
    for ex in (53, 75):
        c.ellipse(f, ex, 72, 5.5, 3.2, rgba("#f2ece4"))
        c.ellipse(f, ex + 0.5, 72, 2.6, 2.8, rgba(eye))
        c.ellipse(f, ex + 1.3, 71, 0.8, 0.8, rgba("#ffffff"))
        c.line(f, [(ex - 7, 64), (ex, 62), (ex + 7, 64)], rgba(brow), 2.2)
    c.line(f, [(64, 74), (62, 86), (66, 88)], shade(skin, 0.7), 1.4)
    c.line(f, [(56, 95), (64, 97), (72, 95)], rgba("#7a3e34"), 1.6)
    c.comp(f)


def portrait_garrick():
    c = Canvas(128, 160)
    portrait_bg(c, "#5a2a22", "#1e1110")
    lay = c.layer()
    c.ellipse(lay, 64, 168, 62, 46, rgba("#8a96a8"))
    c.rect(lay, 50, 126, 78, 160, rgba("#9b2c2c"))
    c.ellipse(lay, 22, 132, 22, 16, rgba("#a3aebf"))
    c.ellipse(lay, 106, 132, 22, 16, rgba("#7f8ba0"))
    c.ellipse(lay, 22, 128, 14, 7, rgba("#c2cad6"))
    c.comp(lay)
    portrait_face(c, "#c99a74")
    hair = c.layer()
    c.poly(hair, [(37, 70), (36, 52), (46, 38), (64, 34), (84, 38), (92, 52), (91, 70), (86, 56),
                  (72, 48), (56, 48), (42, 56)], rgba("#3b2617"))
    c.comp(hair)
    stub = c.layer()
    c.ellipse(stub, 64, 94, 22, 12, rgba("#3b2617", 70))
    face_clip = c.layer()
    c.ellipse(face_clip, 64, 72, 26, 32, rgba("#ffffff"))
    c.comp(stub, clip=face_clip)
    scar = c.layer()
    c.line(scar, [(78, 62), (82, 80)], rgba("#8c5a46"), 1.4)
    c.comp(scar)
    c.outline(rgba("#120c0a"), 1.0)
    return c


def portrait_elowen():
    c = Canvas(128, 160)
    portrait_bg(c, "#2f2552", "#100c1e")
    back_hair = c.layer()
    c.poly(back_hair, [(34, 60), (30, 140), (50, 150), (64, 120), (78, 150), (98, 140), (94, 60)],
           rgba("#d3d8e3"))
    c.comp(back_hair)
    lay = c.layer()
    c.ellipse(lay, 64, 170, 60, 46, rgba("#5b3a8c"))
    c.poly(lay, [(52, 126), (76, 126), (64, 150)], rgba("#432a68"))
    c.rect(lay, 30, 136, 98, 140, rgba("#c9a43a"))
    c.comp(lay)
    portrait_face(c, "#e8cdb2", eye="#3a6e8c", brow="#b9bfcc", pointed=True)
    hair = c.layer()
    c.poly(hair, [(37, 74), (38, 50), (50, 40), (64, 37), (80, 40), (90, 52), (91, 74), (84, 54),
                  (66, 46), (50, 52), (44, 64)], rgba("#e2e6ee"))
    c.comp(hair)
    hat = c.layer()
    c.ellipse(hat, 64, 44, 46, 10, rgba("#432a68"))
    c.poly(hat, [(32, 44), (96, 44), (82, 14), (104, 2), (70, 8), (54, 10)], rgba("#4f3279"))
    c.rect(hat, 36, 36, 92, 44, rgba("#c9a43a"))
    c.ellipse(hat, 64, 40, 4, 4, rgba("#9fe8ff"))
    c.comp(hat)
    c.outline(rgba("#0d0a14"), 1.0)
    return c


def portrait_odran():
    c = Canvas(128, 160)
    portrait_bg(c, "#6a4a1e", "#24170a")
    lay = c.layer()
    c.ellipse(lay, 64, 166, 64, 48, rgba("#d9d2bf"))
    c.rect(lay, 58, 122, 70, 160, rgba("#c9a43a"))
    c.comp(lay)
    portrait_face(c, "#8d5a3b", eye="#3b2a1a", brow="#3e2614")
    shine = c.layer()
    c.ellipse(shine, 54, 48, 9, 5, rgba("#b07a56", 200))
    c.comp(shine)
    beard = c.layer()
    c.poly(beard, [(38, 78), (44, 96), (50, 118), (64, 134), (78, 118), (84, 96), (90, 78), (82, 92),
                   (72, 100), (56, 100), (46, 92)], rgba("#6a3f22"))
    c.poly(beard, [(54, 92), (64, 90), (74, 92), (70, 98), (58, 98)], rgba("#7d4c2a"))
    c.line(beard, [(56, 95), (64, 97), (72, 95)], rgba("#5a2e26"), 1.6)
    for x in (52, 60, 68, 76):
        c.line(beard, [(x, 104), (x + 2, 120)], rgba("#4f2e18"), 1)
    c.comp(beard)
    circ = c.layer()
    c.line(circ, [(38, 56), (64, 48), (90, 56)], rgba("#d8b546"), 3)
    c.ellipse(circ, 64, 49, 4, 4, rgba("#f0cf5a"))
    sun = (64, 142)
    c.ellipse(circ, sun[0], sun[1], 7, 7, rgba("#f0cf5a"))
    for i in range(8):
        a = i * math.pi / 4
        c.line(circ, [(sun[0] + math.cos(a) * 8, sun[1] + math.sin(a) * 8),
                      (sun[0] + math.cos(a) * 12, sun[1] + math.sin(a) * 12)], rgba("#f0cf5a"), 2)
    c.comp(circ)
    c.outline(rgba("#140d06"), 1.0)
    return c


def portrait_wren():
    c = Canvas(128, 160)
    portrait_bg(c, "#1f4440", "#0a1716")
    lay = c.layer()
    c.ellipse(lay, 64, 168, 62, 46, rgba("#2f4a3a"))
    c.poly(lay, [(26, 160), (34, 60), (64, 26), (94, 60), (102, 160)], rgba("#2f4a3a"))
    c.comp(lay)
    portrait_face(c, "#e0b28a", eye="#4c7a3a", brow="#7a3a1e", ears=False)
    hair = c.layer()
    c.poly(hair, [(40, 70), (42, 50), (54, 42), (70, 42), (86, 50), (88, 70), (80, 52), (60, 50),
                  (48, 58)], rgba("#8c3f1f"))
    c.comp(hair)
    hood = c.layer()
    c.poly(hood, [(30, 120), (34, 62), (46, 38), (64, 30), (82, 38), (94, 62), (98, 120), (88, 78),
                  (80, 48), (64, 42), (48, 48), (40, 78)], rgba("#3a5a47"))
    c.ellipse(hood, 64, 46, 28, 8, rgba("#1d3026", 170))
    c.comp(hood)
    mask = c.layer()
    c.poly(mask, [(38, 86), (90, 86), (88, 110), (64, 118), (40, 110)], rgba("#2a2722"))
    c.line(mask, [(42, 92), (86, 92)], rgba("#3a3630"), 1.5)
    c.comp(mask)
    frk = c.layer()
    rng = np.random.default_rng(4)
    for _ in range(14):
        x, y = rng.uniform(46, 82), rng.uniform(76, 84)
        c.ellipse(frk, x, y, 0.9, 0.9, rgba("#a8653e", 180))
    c.comp(frk)
    c.outline(rgba("#081210"), 1.0)
    return c


def portrait_default():
    """Neutral silhouette used when a sheet has no portrait of its own."""
    c = Canvas(128, 160)
    portrait_bg(c, "#3a3a44", "#141418")
    lay = c.layer()
    c.ellipse(lay, 64, 170, 60, 48, rgba("#55555f"))
    c.rect(lay, 52, 96, 76, 128, rgba("#4a4a53"))
    c.ellipse(lay, 64, 72, 26, 32, rgba("#4f4f59"))
    c.comp(lay)
    c.outline(rgba("#0e0e12"), 1.0)
    return c


PORTRAITS = {
    "default": portrait_default,
    "garrick": portrait_garrick,
    "elowen": portrait_elowen,
    "odran": portrait_odran,
    "wren": portrait_wren,
}


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*", choices=["terrain", "props", "characters", "portraits"])
    args = ap.parse_args()
    groups = set(args.only or ["terrain", "props", "characters", "portraits"])

    if "terrain" in groups:
        for name, fn in TERRAIN.items():
            path = ASSETS / "terrain" / f"{name}.png"
            path.parent.mkdir(parents=True, exist_ok=True)
            fn().save(path)
            print("wrote", path.relative_to(ROOT))
    if "props" in groups:
        for name, fn in PROPS.items():
            c, origin = fn()
            path = ASSETS / "props" / f"{name}.png"
            c.save(path)
            print("wrote", path.relative_to(ROOT), "origin", origin)
    if "characters" in groups:
        for name, fn in CHARACTERS.items():
            path = ASSETS / "characters" / f"{name}.png"
            fn().save(path)
            print("wrote", path.relative_to(ROOT))
    if "portraits" in groups:
        for name, fn in PORTRAITS.items():
            path = ASSETS / "portraits" / f"{name}.png"
            fn().save(path)
            print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
