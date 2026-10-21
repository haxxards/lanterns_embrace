#!/usr/bin/env python3
"""Diagrams for docs/PAINTED_STYLE.md, computed with the same formulas the art
uses (the brush filter is imported from tools/art/blender/paint_filter.py).

    python3 tools/art/docs/style_diagrams.py      # -> docs/images/painted_style/*.png

Needs numpy and Pillow only.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/art/blender"))
import paint_filter  # noqa: E402

OUT = ROOT / "docs/images/painted_style"
BG = (28, 24, 20)
PANEL = (38, 33, 28)
TEXT = (232, 226, 214)
DIM = (150, 142, 130)
GOLD = (214, 170, 92)
BLUE = (110, 160, 230)
ORANGE = (230, 140, 60)
RED = (220, 90, 70)
GREEN = (120, 190, 110)


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/" + name, size)
    except OSError:
        return ImageFont.load_default()


F, FB, FS, FT = font(14), font(15, True), font(12), font(20, True)


def canvas(w, h, title=None):
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    if title:
        d.text((16, 12), title, font=FT, fill=TEXT)
    return img, d


def arrow(d, a, b, color, width=3, head=10):
    d.line([a, b], fill=color, width=width)
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    for s in (-1, 1):
        p = (b[0] - head * math.cos(ang + s * 0.45), b[1] - head * math.sin(ang + s * 0.45))
        d.line([b, p], fill=color, width=width)


class Graph:
    """A small line graph: data x in [x0, x1], y in [y0, y1] mapped to a box."""

    def __init__(self, d, box, xr, yr):
        self.d, self.box, self.xr, self.yr = d, box, xr, yr
        l, t, r, b = box
        d.rectangle(box, fill=PANEL)
        d.line([(l, b), (r, b)], fill=DIM, width=1)
        d.line([(l, t), (l, b)], fill=DIM, width=1)

    def p(self, x, y):
        l, t, r, b = self.box
        return (l + (x - self.xr[0]) / (self.xr[1] - self.xr[0]) * (r - l),
                b - (y - self.yr[0]) / (self.yr[1] - self.yr[0]) * (b - t))

    def line(self, xs, ys, color, width=3):
        self.d.line([self.p(x, y) for x, y in zip(xs, ys)], fill=color, width=width)

    def hline(self, y, color, label=None):
        a, b = self.p(self.xr[0], y), self.p(self.xr[1], y)
        for x in range(int(a[0]), int(b[0]), 10):
            self.d.line([(x, a[1]), (x + 5, a[1])], fill=color, width=1)
        if label:
            self.d.text((b[0] + 6, a[1] - 8), label, font=FS, fill=color)

    def fill(self, xs, ys, color):
        pts = [self.p(xs[0], self.yr[0])] + [self.p(x, y) for x, y in zip(xs, ys)] + [self.p(xs[-1], self.yr[0])]
        self.d.polygon(pts, fill=color)


# --------------------------------------------------------------------------
# Edge wear: comparing the true normal with a rounded (bevelled) one
# --------------------------------------------------------------------------

def edge_wear():
    img, d = canvas(1100, 560, "Finding worn edges: true normal vs. rounded normal")
    # Walk along the surface of a block's corner: the top face (s from 0 to 1),
    # then down the side face (s from 1 to 2). The corner is at s = 1.
    r = 0.22  # the Bevel node's search radius, in the same units

    def true_n(s):
        return np.array([0.0, 1.0]) if s < 1 else np.array([1.0, 0.0])

    def bevel_n(s):
        # Average of the true normals within r of s along the surface, renormalised:
        # a 2D stand-in for what the Bevel shader node does in 3D.
        side = min(max((s + r) - 1.0, 0.0), 2 * r) / (2 * r) if s + r > 1 and s - r < 1 else (1.0 if s >= 1 else 0.0)
        v = np.array([side, 1.0 - side])
        return v / np.linalg.norm(v)

    # Left: the block in cross-section with both normals drawn along its surface.
    ox, oy, sc = 90, 470, 300

    def pos(s):
        return (ox + s * sc, oy - sc) if s <= 1 else (ox + sc, oy - sc + (s - 1) * sc)

    d.polygon([(ox, oy - sc), (ox + sc, oy - sc), (ox + sc, oy), (ox, oy)], fill=(70, 62, 54))
    d.text((ox + 20, oy - 40), "a block, cut in half", font=FS, fill=DIM)
    for s in np.linspace(0.35, 1.65, 14):
        p = pos(s)
        t, b = true_n(s), bevel_n(s)
        arrow(d, p, (p[0] + t[0] * 70, p[1] - t[1] * 70), (200, 200, 200), 2, 7)
        arrow(d, p, (p[0] + b[0] * 55, p[1] - b[1] * 55), ORANGE, 3, 8)
    d.text((ox, 60), "white: the true normal (straight out of each face)", font=F, fill=(220, 220, 220))
    d.text((ox, 82), "orange: the Bevel node's normal (as if the corner were rounded)", font=F, fill=ORANGE)
    d.text((ox, oy + 8), "On the flat faces they agree (orange hides white); near the corner they part.", font=FS,
           fill=DIM)

    # Right: 1 - dot(true, bevel) along the surface, the thresholds, and the mask.
    ss = np.linspace(0.3, 1.7, 400)
    v = np.array([1.0 - float(true_n(s) @ bevel_n(s)) for s in ss])
    g = Graph(d, (560, 130, 1000, 300), (0.3, 1.7), (0.0, 0.32))
    g.line(ss, v, BLUE)
    g.hline(0.02, GREEN, "lo = 0.02")
    g.hline(0.22, RED, "hi = 0.22")
    d.text((560, 104), "edge = 1 - dot(true normal, bevel normal)", font=FB, fill=BLUE)
    for s, label in ((0.45, "top face"), (1.0, "corner"), (1.55, "side face")):
        x = g.p(s, 0)[0]
        d.text((x - d.textlength(label, font=FS) / 2, 306), label, font=FS, fill=DIM)
    mask = np.clip((v - 0.02) / (0.22 - 0.02), 0, 1)
    g2 = Graph(d, (560, 370, 1000, 490), (0.3, 1.7), (0.0, 1.1))
    g2.fill(ss, mask, (180, 160, 120))
    g2.line(ss, mask, TEXT, 2)
    d.text((560, 344), "mask = Map Range(edge, 0.02 -> 0, 0.22 -> 1), clamped", font=FB, fill=TEXT)
    d.text((560, 498), "1 on the corner, 0 on flat faces: where paint and dirt rub off.", font=F, fill=DIM)
    d.text((560, 518), "Multiplying by noise then breaks the line into chips.", font=F, fill=DIM)
    img.save(OUT / "diagram_edge_wear.png", optimize=True)


# --------------------------------------------------------------------------
# Kuwahara: the eight slices, and why it keeps edges sharp
# --------------------------------------------------------------------------

def kuwahara():
    img, d = canvas(1100, 700, "The brush filter (generalised Kuwahara)")
    kernels = paint_filter.sector_kernels(5, 8)
    d.text((16, 48), "1. Around every pixel, eight overlapping pie slices of its neighbours (radius 5 px). "
           "Brighter = counts more.", font=F, fill=TEXT)
    cell = 11 * 10
    for k, ker in enumerate(kernels):
        v = (ker / ker.max() * 255).astype(np.uint8)
        heat = np.stack([v, (v * 0.75).astype(np.uint8), (v * 0.45).astype(np.uint8)], -1)
        tile = Image.fromarray(heat).resize((cell, cell), Image.NEAREST)
        x = 16 + k * (cell + 22)
        img.paste(tile, (x, 76))
        dd = ImageDraw.Draw(img)
        dd.rectangle((x + 50, 76 + 50, x + 59, 76 + 59), outline=(90, 200, 255))
        ang = -180 + (k + 0.5) * 45
        dd.text((x + 22, 76 + cell + 4), f"slice {k + 1}: {ang:+.0f} deg", font=FS, fill=DIM)
    d.text((16, 210), "   (the blue square is the pixel being painted; it sits at the tip of every slice)", font=FS,
           fill=DIM)

    # A test picture: a noisy dark area meeting a noisy light one along a slanted edge.
    rng = np.random.default_rng(3)
    n = 48
    yy, xx = np.mgrid[0:n, 0:n]
    light = (xx + 0.4 * yy) > n * 0.62
    base = np.where(light[..., None], np.array([0.78, 0.62, 0.42]), np.array([0.28, 0.2, 0.14]))
    grain = rng.normal(0, 0.06, (n, n, 1)) + rng.normal(0, 0.02, (n, n, 3))  # mostly light/dark speckle
    pic = np.clip(base + grain, 0, 1)
    alpha = np.ones((n, n))
    padded = np.pad(pic, ((5, 5), (5, 5), (0, 0)), mode="reflect")
    box = paint_filter._Convolver(padded.shape[:2], np.ones((11, 11)) / 121)
    edge_rows = np.clip(np.stack([box(padded[..., c]) for c in range(3)], -1)[5:-5, 5:-5], 0, 1)
    kuw = paint_filter.kuwahara(pic, alpha, radius=5)
    y0 = 250
    d.text((16, y0), "2. Each slice gets its average colour and how much the colour varies inside it. "
           "The calmest slices win (weight = 1 / variation^6).", font=F, fill=TEXT)
    for i, (label, arr) in enumerate((("input: noisy, with an edge", pic), ("ordinary blur: smears the edge", edge_rows),
                                      ("Kuwahara: smooth patches, crisp edge", kuw))):
        tile = Image.fromarray((arr * 255).astype(np.uint8)).resize((n * 5, n * 5), Image.NEAREST)
        x = 16 + i * (n * 5 + 30)
        img.paste(tile, (x, y0 + 30))
        d.text((x, y0 + 36 + n * 5), label, font=F, fill=DIM)
    # The weights of the eight slices for one pixel just on the dark side of the edge.
    py, px = 24, 22
    while light[py, px + 1] is np.False_ or light[py, px]:
        px -= 1
    sig, wts = [], []
    for ker in kernels:
        r = 5
        win = pic[py - r:py + r + 1, px - r:px + r + 1]
        m = (win * ker[..., None]).sum((0, 1))
        m2 = (win ** 2 * ker[..., None]).sum((0, 1))
        s = np.sqrt(np.clip(m2 - m * m, 0, None)).sum()
        sig.append(s)
        wts.append(1 / (1e-4 + s) ** 6)
    wts = np.array(wts) / sum(wts)
    for i in range(3):
        x = 16 + i * (n * 5 + 30)
        d.rectangle((x + px * 5, y0 + 30 + py * 5, x + px * 5 + 4, y0 + 30 + py * 5 + 4), outline=(90, 200, 255),
                    width=2)
    gx = 16 + 3 * (n * 5 + 30)
    d.text((gx, y0 + 30), "the blue pixel's slices:", font=FB, fill=TEXT)
    for k in range(8):
        yb = y0 + 60 + k * 26
        ang = -180 + (k + 0.5) * 45
        d.text((gx, yb), f"{ang:+5.0f} deg", font=FS, fill=DIM)
        d.rectangle((gx + 70, yb + 2, gx + 70 + int(wts[k] * 80), yb + 16), fill=GOLD)
        d.text((gx + 76 + int(wts[k] * 80), yb + 1), f"{wts[k] * 100:4.1f}%  var {sig[k]:.2f}", font=FS, fill=DIM)
    d.text((16, y0 + 330), "Slices that cross the edge mix dark and light, so they vary a lot and get almost no say. "
           "Slices that stay on the dark side", font=F, fill=TEXT)
    d.text((16, y0 + 350), "are calm and decide the colour, so the pixel stays dark and the edge stays sharp, "
           "while the noise inside each area averages away.", font=F, fill=TEXT)
    d.text((16, y0 + 380), "On a render this turns fine texture into flat strokes of colour that follow the shapes, "
           "which is what makes it look painted.", font=F, fill=DIM)
    img.save(OUT / "diagram_kuwahara.png", optimize=True)


# --------------------------------------------------------------------------
# Mail rings: the pattern built step by step
# --------------------------------------------------------------------------

def mail_rings():
    img, d = canvas(1100, 400, "Mail rings from arithmetic (painted._ring_pattern)")
    n, span, scale = 240, 0.2, 34.0
    zz, xx = np.mgrid[0:n, 0:n] / n * span
    zz = zz[::-1]  # z grows upwards in the picture
    x, z = xx * scale, zz * scale * 1.15
    row = np.floor(z)
    shift = np.mod(row, 2.0) * 0.5
    fx = (x + shift) % 1.0 - 0.5
    fz = z % 1.0 - 0.5
    dist = np.sqrt(fx * fx + fz * fz)
    band = np.abs(dist - 0.36)
    ring = np.clip((band - 0.16) / (0.02 - 0.16), 0, 1)
    cell_id = (np.floor(x + shift) + row * 7) % 2
    steel, gap = np.array([0.71, 0.73, 0.75]), np.array([0.15, 0.145, 0.137])
    panels = [
        ("1. rows: floor(z)", np.where((row % 2)[..., None] > 0, [0.55, 0.42, 0.3], [0.3, 0.24, 0.2])),
        ("2. odd rows shifted half a ring", np.where(cell_id[..., None] > 0, [0.55, 0.42, 0.3], [0.3, 0.24, 0.2])),
        ("3. distance from each cell's centre", np.repeat((dist / 0.71)[..., None], 3, -1)),
        ("4. ring = near distance 0.36", np.repeat(ring[..., None], 3, -1)),
        ("5. colour: dark gaps, steel rings", gap + (steel - gap) * ring[..., None]),
    ]
    size = 200
    for i, (label, arr) in enumerate(panels):
        tile = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
        px = 16 + i * (size + 16)
        img.paste(tile, (px, 60))
        d.text((px, 268), label, font=FS, fill=TEXT)
    d.text((16, 300), "x and z are the surface's own coordinates times the ring count (34 per unit). "
           "floor() numbers the rows; odd rows slide", font=F, fill=DIM)
    d.text((16, 320), "half a ring (the stagger of real mail); fract() - 0.5 gives each spot's offset from its cell "
           "centre; Pythagoras gives the distance;", font=F, fill=DIM)
    d.text((16, 340), "points about 0.36 from a centre are wire. The same ring value also feeds the bump, so the "
           "rings catch light like raised metal.", font=F, fill=DIM)
    img.save(OUT / "diagram_mail_rings.png", optimize=True)


# --------------------------------------------------------------------------
# The light rig, seen from above
# --------------------------------------------------------------------------

def light_rig():
    img, d = canvas(1100, 520, "The studio lights (painted.studio), seen from above")
    lights = [("Key", (-3.0, -3.5, 5.0), 520, (255, 235, 199), "warm, upper left: the main light"),
              ("Fill", (4.0, -2.5, 1.5), 150, (255, 204, 158), "warm, low right: lifts the shadows"),
              ("Rim", (2.5, 4.0, 3.0), 520, (158, 199, 255), "cool, from behind: outlines the shape"),
              ("Top", (0.0, 0.5, 6.0), 104, (255, 245, 230), "soft, overhead: gentle top light")]
    cx, cy, sc = 300, 280, 42
    d.rectangle((40, 60, 560, 500), fill=PANEL)
    d.text((50, 66), "north (away from the viewer)", font=FS, fill=DIM)
    d.text((50, 482), "south (the camera)", font=FS, fill=DIM)
    d.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), fill=(120, 110, 100))
    d.text((cx + 18, cy - 8), "item", font=FS, fill=DIM)
    arrow(d, (cx, 470), (cx, cy + 30), DIM, 2, 9)
    d.text((cx + 8, 440), "camera looks north", font=FS, fill=DIM)
    for name, (x, y, z), energy, color, _ in lights:
        px, py = cx + x * sc, cy - y * sc
        r = 8 + energy / 40
        d.ellipse((px - r, py - r, px + r, py + r), fill=color)
        d.line([(px, py), (cx, cy)], fill=color, width=1)
        d.text((px + r + 4, py - 8), f"{name} ({z:.1f} up)", font=F, fill=color)
    for i, (name, _, energy, color, note) in enumerate(lights):
        d.text((600, 90 + i * 60), f"{name}: {energy:.0f} W", font=FB, fill=color)
        d.text((600, 112 + i * 60), note, font=F, fill=DIM)
    d.text((600, 350), "Warm light against a cool rim is the classic", font=F, fill=TEXT)
    d.text((600, 370), "painter's trick: it separates the object from", font=F, fill=TEXT)
    d.text((600, 390), "the background and gives every edge a colour.", font=F, fill=TEXT)
    d.text((600, 420), "The sky behind is a dim grey (0.5), so metal", font=F, fill=DIM)
    d.text((600, 440), "reflects mostly darkness and the lights' shapes.", font=F, fill=DIM)
    img.save(OUT / "diagram_light_rig.png", optimize=True)


# --------------------------------------------------------------------------
# The whole pipeline
# --------------------------------------------------------------------------

def pipeline():
    img, d = canvas(1100, 330, "From script to inventory slot")
    steps = [("1. Model", "render_items_painted.py", "shapes built in Python"),
             ("2. Materials", "painted.py", "variation, grime, wear"),
             ("3. Lights", "painted.studio()", "warm key, cool rim, AgX"),
             ("4. Render", "Blender Cycles", "512 x 512, transparent"),
             ("5. Finish", "paint_filter.py", "brushes, colour, ink"),
             ("6. Shrink", "render_icon()", "64 px, sharpen, shadow")]
    w, h, gap = 166, 96, 14
    for i, (title, where, what) in enumerate(steps):
        x = 16 + i * (w + gap)
        d.rounded_rectangle((x, 60, x + w, 60 + h), 10, fill=PANEL, outline=GOLD)
        d.text((x + 10, 68), title, font=FB, fill=GOLD)
        d.text((x + 10, 92), where, font=FS, fill=TEXT)
        d.text((x + 10, 112), what, font=FS, fill=DIM)
        if i < len(steps) - 1:
            arrow(d, (x + w + 1, 60 + h / 2), (x + w + gap - 1, 60 + h / 2), GOLD, 2, 6)
    d.rounded_rectangle((16, 200, 520, 300), 10, fill=PANEL, outline=BLUE)
    d.text((28, 208), "assets/items/painted/longsword.png", font=FB, fill=BLUE)
    d.text((28, 234), "assets/items/longsword.png  (classic, unchanged)", font=F, fill=DIM)
    d.text((28, 260), "same file name in both folders", font=FS, fill=DIM)
    d.rounded_rectangle((580, 200, 1084, 300), 10, fill=PANEL, outline=GREEN)
    d.text((592, 208), 'game_config.json:  "art_style": {"items": "painted"}', font=FB, fill=GREEN)
    d.text((592, 234), "GameConfig.styled_path() picks the folder when the", font=F, fill=TEXT)
    d.text((592, 254), "game loads; the Esc menu's \"Item icons\" button flips it.", font=F, fill=TEXT)
    arrow(d, (16 + 5 * (w + gap) + w / 2, 60 + h), (400, 198), BLUE, 2, 8)
    arrow(d, (522, 250), (578, 250), GREEN, 2, 8)
    img.save(OUT / "diagram_pipeline.png", optimize=True)


# --------------------------------------------------------------------------
# Map Range and Mix, the two operations everything is built from
# --------------------------------------------------------------------------

def map_and_mix():
    img, d = canvas(1100, 330, "The two building blocks: Map Range and Mix")
    g = Graph(d, (40, 90, 480, 280), (0.0, 0.3), (0.0, 1.1))
    xs = np.linspace(0, 0.3, 200)
    g.line(xs, np.clip((xs - 0.02) / 0.2, 0, 1), GOLD)
    g.hline(1.0, DIM, "1")
    d.text((40, 50), "Map Range: out = (value - lo) / (hi - lo),", font=FB, fill=GOLD)
    d.text((40, 70), "then kept between 0 and 1", font=FB, fill=GOLD)
    for v, label in ((0.02, "lo 0.02"), (0.22, "hi 0.22"), (0.3, "0.3")):
        x = g.p(v, 0)[0]
        d.text((max(40, x - d.textlength(label, font=FS) / 2), 286), label, font=FS, fill=DIM)
    d.text((40, 306), "Turns any measurement into a 0-1 'how much' (a mask).", font=F, fill=DIM)
    d.text((580, 50), "Mix: out = A + (B - A) x factor", font=FB, fill=GOLD)
    a, b = np.array([0.12, 0.09, 0.07]), np.array([0.62, 0.43, 0.27])
    bar = np.linspace(0, 1, 440)[None, :, None] * (b - a) + a
    bar = np.repeat(bar, 60, 0)
    img.paste(Image.fromarray((bar * 255).astype(np.uint8)), (580, 110))
    d.text((580, 176), "factor 0: A (grime colour)", font=FS, fill=DIM)
    d.text((880, 176), "factor 1: B (wood)", font=FS, fill=DIM)
    d.text((580, 210), "Feed a mask in as the factor and the colour changes", font=F, fill=TEXT)
    d.text((580, 230), "only where the mask says so: grime where the crevice", font=F, fill=TEXT)
    d.text((580, 250), "mask is high, pale paint where the edge mask is high.", font=F, fill=TEXT)
    d.text((580, 276), "'Multiply' mode instead scales the colour: x 0.9 is", font=F, fill=DIM)
    d.text((580, 296), "10% darker, x 1.1 is 10% lighter.", font=F, fill=DIM)
    img.save(OUT / "diagram_map_and_mix.png", optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for fn in (pipeline, map_and_mix, edge_wear, mail_rings, light_rig, kuwahara):
        fn()
        print("wrote", fn.__name__)


if __name__ == "__main__":
    main()
