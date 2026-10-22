#!/usr/bin/env python3
"""Turns the frames recorded by tests/tools/fx_capture.tscn (tests/output/fx/)
into the docs' pictures: docs/images/fx_sword.gif, fx_magic_missile.gif and
the labelled strip fx_all.jpg.

    pip install pillow
    python3 tools/capture/fx_gifs.py

The capture slows the game to 0.15x and saves every frame, which comes to
about 20 ms of game time per frame; every second frame at 40 ms plays back
at about real speed.
"""
import glob
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FRAMES = ROOT / "tests" / "output" / "fx"
OUT = ROOT / "docs" / "images"


def gif(name, out, stop, width=420, step=2, ms=40, hold=700):
    files = sorted(glob.glob(str(FRAMES / f"{name}_*.png")))[:stop:step]
    frames = []
    for f in files:
        im = Image.open(f).convert("RGB")
        frames.append(im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
                      .quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    durations = [ms] * len(frames)
    durations[-1] = hold
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
    print("wrote", out)


def strip(out, keys, tile=(300, 200)):
    tw, th = tile
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    sheet = Image.new("RGB", (tw * 4, th * ((len(keys) + 3) // 4)), (20, 18, 16))
    for k, (label, name, i) in enumerate(keys):
        im = Image.open(FRAMES / f"{name}_{i:03d}.png").convert("RGB")
        w, h = im.size
        cw, ch = min(w, int(h * 1.5)), min(h, int(w / 1.5))
        t = im.crop(((w - cw) // 2, (h - ch) // 2, (w + cw) // 2, (h + ch) // 2)).resize(tile, Image.LANCZOS)
        d = ImageDraw.Draw(t)
        d.rectangle((0, th - 24, tw, th), fill=(20, 18, 16))
        d.text((8, th - 21), label, fill=(230, 194, 106), font=font)
        sheet.paste(t, ((k % 4) * tw, (k // 4) * th))
    sheet.save(out, quality=86)
    print("wrote", out)


if __name__ == "__main__":
    gif("sword", OUT / "fx_sword.gif", stop=44)
    gif("magic_missile", OUT / "fx_magic_missile.gif", stop=80, width=360)
    strip(OUT / "fx_all.jpg", [("Longsword: slash", "sword", 10), ("Mace: smash", "mace", 12),
                               ("Thrown dagger", "thrown", 16), ("Arrow", "arrow", 14),
                               ("Fire Bolt", "fire_bolt", 22), ("Magic Missile", "magic_missile", 30),
                               ("Wolf: bite", "bite", 10), ("Impact", "sword", 14)])
