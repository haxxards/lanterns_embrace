#!/usr/bin/env python3
"""The four items the painted style was first tested on, set against the
reference art they were matched to: a crop of the reference, the classic icon
and the painted icon (both enlarged with hard pixels).

    python3 tools/art/docs/compare_with_reference.py   # -> docs/images/painted_style/reference_compared.png

Needs Pillow only (and its WebP support, which standard builds include).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
IMAGES = ROOT / "docs/images/painted_style"
REFERENCE = IMAGES / "reference.webp"
# item icon name -> (label, crop box in the reference: left, top, right, bottom)
ITEMS = [("longsword", "Longsword", (612, 650, 722, 1015)),
         ("shield", "Shield", (865, 85, 1045, 275)),
         ("potion_of_healing", "Potion of Healing", (665, 380, 790, 580)),
         ("chain_mail", "Chain Mail", (1740, 785, 1945, 1035))]
BG, CELL, TEXT, DIM, GOLD = (28, 24, 20), (38, 33, 28), (232, 226, 214), (150, 142, 130), (214, 170, 92)


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/" + name, size)
    except OSError:
        return ImageFont.load_default()


def main():
    ref = Image.open(REFERENCE).convert("RGB")
    rows = [("Reference", "crop of reference.webp"), ("Classic", "the game's 64 px icon, 3x"),
            ("Painted", "the game's 64 px icon, 3x")]
    cw, ch, lw, top = 236, 236, 190, 56
    sheet = Image.new("RGB", (lw + cw * len(ITEMS) + 10, top + ch * len(rows) + 10), BG)
    d = ImageDraw.Draw(sheet)
    for i, (_, label, _) in enumerate(ITEMS):
        x = lw + i * cw
        d.text((x + (cw - 10 - d.textlength(label, font=font(16, True))) / 2, 22), label, font=font(16, True),
               fill=GOLD)
    for r, (label, note) in enumerate(rows):
        y = top + r * ch
        d.text((16, y + ch / 2 - 18), label, font=font(16, True), fill=TEXT)
        d.text((16, y + ch / 2 + 4), note, font=font(12), fill=DIM)
    for i, (name, _, box) in enumerate(ITEMS):
        x = lw + i * cw
        pics = [ref.crop(box),
                Image.open(ROOT / "assets/items" / f"{name}.png").convert("RGBA"),
                Image.open(ROOT / "assets/items/painted" / f"{name}.png").convert("RGBA")]
        for r, pic in enumerate(pics):
            y = top + r * ch
            d.rounded_rectangle((x, y, x + cw - 10, y + ch - 10), 8, fill=CELL)
            if r == 0:
                pic.thumbnail((cw - 30, ch - 30), Image.LANCZOS)
            else:
                pic = pic.resize((192, 192), Image.NEAREST)
            px, py = x + (cw - 10 - pic.width) // 2, y + (ch - 10 - pic.height) // 2
            if pic.mode == "RGBA":
                sheet.paste(pic, (px, py), pic)
            else:
                sheet.paste(pic, (px, py))
    out = IMAGES / "reference_compared.png"
    sheet.save(out, optimize=True)
    print("wrote", out, sheet.size)


if __name__ == "__main__":
    main()
