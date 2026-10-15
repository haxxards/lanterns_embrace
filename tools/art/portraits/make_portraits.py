#!/usr/bin/env python3
"""Crops sidebar portraits from public-domain paintings.

The paintings come from The Metropolitan Museum of Art's Open Access collection, which
releases images of public-domain works under CC0. The images are fetched from the
museum's public Google Cloud bucket (gcs-public-data--met), cached, then cropped to
4:5 around the face and resized.

    python3 tools/art/portraits/make_portraits.py            # all portraits
    python3 tools/art/portraits/make_portraits.py garrick    # just one
    python3 tools/art/portraits/make_portraits.py --sheet out.png   # contact sheet

Needs Pillow. Edit portraits.json to change the paintings or the crops.
"""
import argparse
import json
import os
import pathlib
import urllib.request

from PIL import Image, ImageEnhance, ImageFilter, ImageStat

Image.MAX_IMAGE_PIXELS = None
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT_DIR = ROOT / "assets" / "portraits"
BUCKET = "https://storage.googleapis.com/gcs-public-data--met/{id}/0.jpg"
CACHE = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache")) / "lanterns_embrace" / "met"
FACE_FROM_TOP = 0.40   # where the face centre sits in the crop
TARGET_MEAN = 0.36     # dark paintings are lifted towards this mean luminance


def fetch(met_id: int) -> pathlib.Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{met_id}.jpg"
    if not path.exists():
        print(f"  downloading Met object {met_id}")
        urllib.request.urlretrieve(BUCKET.format(id=met_id), path)
    return path


def crop_box(w: int, h: int, cx: float, cy: float, ch: float, aspect: float):
    crop_h = ch * h
    crop_w = crop_h * aspect
    if crop_w > w:  # painting too narrow: shrink the crop to fit
        crop_w = w
        crop_h = crop_w / aspect
    left = min(max(cx * w - crop_w / 2, 0), w - crop_w)
    top = min(max(cy * h - crop_h * FACE_FROM_TOP, 0), h - crop_h)
    return (round(left), round(top), round(left + crop_w), round(top + crop_h))


def make(entry: dict, size) -> Image.Image:
    src = Image.open(fetch(entry["met_id"])).convert("RGB")
    cx, cy, ch = entry["crop"]
    im = src.crop(crop_box(src.width, src.height, cx, cy, ch, size[0] / size[1]))
    im = im.resize(tuple(size), Image.LANCZOS)
    # Old varnished paintings are dark: lift the mids so they read at 64x80 in the
    # sidebar, without touching the colour balance.
    mean = sum(ImageStat.Stat(im.convert("L")).mean) / 255.0
    lift = entry.get("lift", 1.0)
    if mean < TARGET_MEAN:
        lift *= min((TARGET_MEAN / max(mean, 0.05)) ** 0.5, 1.45)
    if abs(lift - 1.0) > 0.01:
        gamma = 1.0 / lift
        im = im.point(lambda v: round(255 * (v / 255.0) ** gamma))
    im = ImageEnhance.Contrast(im).enhance(entry.get("contrast", 1.05))
    return im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="portrait ids to build (default: all)")
    ap.add_argument("--sheet", help="also write a contact sheet of the results to this path")
    args = ap.parse_args()
    cfg = json.loads((HERE / "portraits.json").read_text())
    size = cfg["size"]
    built = []
    for entry in cfg["portraits"]:
        if args.ids and entry["id"] not in args.ids:
            continue
        print(f"{entry['id']}: {entry['title']} ({entry['artist']})")
        im = make(entry, size)
        im.save(OUT_DIR / f"{entry['id']}.png", optimize=True)
        built.append(im)
    if args.sheet and built:
        sheet = Image.new("RGB", (size[0] * len(built), size[1]), (20, 20, 20))
        for i, im in enumerate(built):
            sheet.paste(im, (i * size[0], 0))
        sheet.save(args.sheet)


if __name__ == "__main__":
    main()
