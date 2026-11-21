#!/usr/bin/env python3
"""
Verification script for art assets in 'Do Not Wake'.
Validates:
1. File existence
2. Valid PNG header and format
3. Exact dimensions
4. Binary alpha (0 or 255 only)
5. Strict adherence to data/palette.json 15 colors
"""

import os
import sys
import json
from PIL import Image

def hex_to_rgb(hex_str):
    hex_str = hex_str.lstrip('#')
    return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))

def load_palette(palette_path):
    with open(palette_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    palette = {}
    for k, v in data.items():
        if k != "roles" and isinstance(v, str) and v.startswith("#"):
            palette[k] = hex_to_rgb(v)
    return palette

REQUIRED_ASSETS = {
    "docs/keyart.png": (1280, 720),
    "assets/sprites/ui/diag_frame.png": (960, 420),
    "assets/sprites/ui/doc_reader_bg.png": (920, 560),
    "assets/sprites/ui/card_tab.png": (48, 24),
    "assets/sprites/ui/glitch_strip.png": (256, 16),
    "assets/sprites/ui/doc_folder.png": (64, 64),
    "assets/sprites/ui/diag_needle.png": (32, 64),
}

def verify_assets(base_dir="."):
    palette_path = os.path.join(base_dir, "data", "palette.json")
    if not os.path.exists(palette_path):
        print(f"[FAIL] Palette file not found: {palette_path}")
        return False

    palette_dict = load_palette(palette_path)
    allowed_rgb = set(palette_dict.values())
    print(f"Loaded {len(allowed_rgb)} palette colors from {palette_path}")

    all_passed = True

    for rel_path, expected_dims in REQUIRED_ASSETS.items():
        full_path = os.path.join(base_dir, rel_path)
        print(f"\n--- Checking: {rel_path} ---")
        if not os.path.exists(full_path):
            print(f"  [MISSING] File does not exist: {full_path}")
            all_passed = False
            continue

        # Check PNG header
        with open(full_path, "rb") as f:
            header = f.read(8)
            if header != b"\x89PNG\r\n\x1a\n":
                print(f"  [FAIL] Invalid PNG header: {header}")
                all_passed = False
                continue

        try:
            with Image.open(full_path) as img:
                img_format = img.format
                width, height = img.size

                if img_format != "PNG":
                    print(f"  [FAIL] Format is not PNG ({img_format})")
                    all_passed = False

                if (width, height) != expected_dims:
                    print(f"  [FAIL] Dimensions mismatch: expected {expected_dims}, got ({width}, {height})")
                    all_passed = False
                else:
                    print(f"  [OK] Dimensions match: {expected_dims}")

                # Check alpha and colors
                rgba_img = img.convert("RGBA")
                colors = rgba_img.getcolors(maxcolors=width * height + 10)
                
                invalid_alpha = 0
                non_palette_colors = set()

                if colors:
                    for count, (r, g, b, a) in colors:
                        if a not in (0, 255):
                            invalid_alpha += count
                        if a > 0:
                            rgb = (r, g, b)
                            if rgb not in allowed_rgb:
                                non_palette_colors.add(rgb)
                else:
                    # Fallback if too many colors
                    pix = rgba_img.load()
                    for y in range(height):
                        for x in range(width):
                            r, g, b, a = pix[x, y]
                            if a not in (0, 255):
                                invalid_alpha += 1
                            if a > 0:
                                rgb = (r, g, b)
                                if rgb not in allowed_rgb:
                                    non_palette_colors.add(rgb)

                if invalid_alpha > 0:
                    print(f"  [FAIL] Non-binary alpha detected ({invalid_alpha} pixels with alpha != 0 and != 255)")
                    all_passed = False
                else:
                    print(f"  [OK] Alpha is strictly binary (0 or 255)")

                if non_palette_colors:
                    print(f"  [FAIL] {len(non_palette_colors)} colors not in palette found!")
                    for c in list(non_palette_colors)[:5]:
                        print(f"    Sample illegal RGB: {c} / #{c[0]:02X}{c[1]:02X}{c[2]:02X}")
                    all_passed = False
                else:
                    print(f"  [OK] All visible pixels strictly match palette.json (15 colors)")

        except Exception as e:
            print(f"  [ERROR] Failed to open/verify {full_path}: {e}")
            all_passed = False

    return all_passed

if __name__ == "__main__":
    success = verify_assets(".")
    if success:
        print("\n>>> ALL ASSET CHECKS PASSED SUCCESSFULLY! <<<")
        sys.exit(0)
    else:
        print("\n>>> ASSET VERIFICATION FAILED! <<<")
        sys.exit(1)
