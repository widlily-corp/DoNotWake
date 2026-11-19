#!/usr/bin/env python3
"""Чистка сгенерированных спрайтов под палитру проекта.

Что делает:
  1) убирает остатки магенты (#FF00FF) и близких цветов;
  2) убивает полупрозрачные края (антиалиасинг) — только 0 или 255;
  3) квантует цвета до палитры из data/palette.json;
  4) опционально обрезает прозрачные поля.

Использование:
    python tools/clean_sprite.py assets/sprites/robot/robot_calm.png out.png --trim
"""

import argparse
import json
import os

from PIL import Image

DEFAULT_PALETTE = os.path.join("data", "palette.json")


def load_palette(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    colors = []
    for key, value in data.items():
        if key == "roles":
            continue
        if isinstance(value, str) and value.startswith("#") and len(value) == 7:
            colors.append(tuple(int(value[i:i + 2], 16) for i in (1, 3, 5)))
    return colors


def strip_magenta(img):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and r > 170 and b > 170 and g < 100:
                px[x, y] = (0, 0, 0, 0)
    return img


def kill_semi_alpha(img, threshold):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a >= threshold else 0)
    return img


def quantize(img, colors):
    palette = Image.new("P", (1, 1))
    flat = []
    for c in colors:
        flat.extend(c)
    # Fill remaining entries with the first palette color (obsidian) to prevent mapping to (0, 0, 0)
    flat.extend(list(colors[0]) * (256 - len(colors)))
    palette.putpalette(flat)

    rgb = img.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(img.split()[3])
    return out


def main():
    parser = argparse.ArgumentParser(description="Clean a sprite to project palette")
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--palette", default=DEFAULT_PALETTE)
    parser.add_argument("--threshold", type=int, default=128, help="alpha cutoff")
    parser.add_argument("--trim", action="store_true", help="crop transparent border")
    parser.add_argument("--pad", type=int, default=0, help="padding after trim")
    args = parser.parse_args()

    img = Image.open(args.input).convert("RGBA")
    img = strip_magenta(img)
    img = kill_semi_alpha(img, args.threshold)

    if args.trim:
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)
            if args.pad:
                w, h = img.size
                framed = Image.new("RGBA", (w + args.pad * 2, h + args.pad * 2), (0, 0, 0, 0))
                framed.paste(img, (args.pad, args.pad))
                img = framed

    colors = load_palette(args.palette)
    img = quantize(img, colors)
    img.save(args.output)
    print(f"saved {args.output} {img.size} colors={len(set(img.getdata()))}")


if __name__ == "__main__":
    main()
