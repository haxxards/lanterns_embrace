#!/usr/bin/env python3
"""Side-by-side sheet of every item icon in the classic and the painted style.

    python3 tools/art/docs/compare_icon_styles.py                  # -> docs/images/painted_style/icons_compared.png
    python3 tools/art/docs/compare_icon_styles.py --scale 3 --out /tmp/sheet.png

Each item shows its classic icon on the left and its painted icon on the
right, enlarged with hard pixels so you see exactly what the game draws.
Needs Pillow only.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
BG, CELL, SLOT, TEXT, DIM, GOLD = (24, 21, 18), (36, 31, 26), (21, 17, 13), (232, 226, 214), (150, 142, 130), \
    (214, 170, 92)


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scale", type=int, default=2, help="pixel enlargement (default 2)")
    ap.add_argument("--columns", type=int, default=6)
    ap.add_argument("--classic", default=str(ROOT / "assets/items"))
    ap.add_argument("--painted", default=str(ROOT / "assets/items/painted"))
    ap.add_argument("--out", default=str(ROOT / "docs/images/painted_style/icons_compared.png"))
    args = ap.parse_args()

    items = json.loads((ROOT / "data/items/items.json").read_text())["items"]
    entries = [(key, d["name"], Path(d["icon"].replace("res://", "")).name) for key, d in items.items()]
    seen, unique = set(), []
    for key, name, file in entries:  # several items can share one icon
        if file not in seen:
            seen.add(file)
            unique.append((name, file))

    icon = 64 * args.scale
    pad, gap, label_h = 14, 8, 22
    cw = pad * 2 + icon * 2 + gap
    ch = pad + icon + label_h + pad
    cols = args.columns
    rows = (len(unique) + cols - 1) // cols
    head = 70
    sheet = Image.new("RGB", (cols * cw + 20, head + rows * ch + 20), BG)
    d = ImageDraw.Draw(sheet)
    d.text((14, 12), "Item icons: classic (left) and painted (right)", font=font(BOLD, 22), fill=TEXT)
    d.text((14, 42), f"Shown at {args.scale}x with hard pixels: what the game draws in a 56 px slot.",
           font=font(FONT, 13), fill=DIM)
    f_name = font(FONT, 13)
    for i, (name, file) in enumerate(unique):
        x0 = 10 + (i % cols) * cw
        y0 = head + (i // cols) * ch
        d.rounded_rectangle((x0 + 3, y0 + 3, x0 + cw - 3, y0 + ch - 3), 8, fill=CELL)
        for k, folder in enumerate((args.classic, args.painted)):
            px = x0 + pad + k * (icon + gap)
            d.rectangle((px, y0 + pad, px + icon - 1, y0 + pad + icon - 1), fill=SLOT)
            path = Path(folder) / file
            if path.exists():
                im = Image.open(path).convert("RGBA").resize((icon, icon), Image.NEAREST)
                sheet.paste(im, (px, y0 + pad), im)
            else:
                d.text((px + 8, y0 + pad + icon // 2 - 8), "missing", font=f_name, fill=(200, 80, 70))
        tw = d.textlength(name, font=f_name)
        d.text((x0 + (cw - tw) / 2, y0 + pad + icon + 4), name, font=f_name, fill=GOLD)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.out, optimize=True)
    print("wrote", args.out, sheet.size)


if __name__ == "__main__":
    main()
