#!/usr/bin/env python3
"""
Generate all required 2D art assets and key art for 'Do Not Wake'.
Strictly adheres to:
- 15-color palette from data/palette.json
- Exact pixel dimensions
- Binary alpha (0 or 255)
- Hi-res pixel-art aesthetic
"""

import os
import json
import numpy as np
from PIL import Image, ImageDraw

PALETTE_PATH = os.path.join("data", "palette.json")

def load_palette():
    with open(PALETTE_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    palette = {}
    for k, v in data.items():
        if k != "roles" and isinstance(v, str) and v.startswith("#"):
            r = int(v[1:3], 16)
            g = int(v[3:5], 16)
            b = int(v[5:7], 16)
            palette[k] = (r, g, b)
    return palette

PAL = load_palette()

def quantize_to_palette(img, palette_dict):
    colors = list(palette_dict.values())
    flat = []
    for c in colors:
        flat.extend(c)
    flat.extend(list(colors[0]) * (256 - len(colors)))
    
    pal_img = Image.new("P", (1, 1))
    pal_img.putpalette(flat)
    
    # Quantize RGB
    rgb = img.convert("RGB").quantize(palette=pal_img, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.convert("RGBA")
    
    # Preserve binary alpha from original
    orig_a = img.split()[3]
    bin_a = orig_a.point(lambda p: 255 if p >= 128 else 0)
    out.putalpha(bin_a)
    return out

# ==============================================================================
# 1. diag_frame.png (960x420)
# CRT oscilloscope diagnostics panel frame with transparent viewport
# ==============================================================================
def generate_diag_frame():
    w, h = 960, 420
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # Frame outer body
    # Base casing in storm_gray
    draw.rectangle([0, 0, w - 1, h - 1], fill=(*PAL["storm_gray"], 255))
    
    # Corner chamfers (cut 4px off 4 corners)
    for i in range(4):
        for j in range(4 - i):
            im.putpixel((i, j), (0, 0, 0, 0))
            im.putpixel((w - 1 - i, j), (0, 0, 0, 0))
            im.putpixel((i, h - 1 - j), (0, 0, 0, 0))
            im.putpixel((w - 1 - i, h - 1 - j), (0, 0, 0, 0))
            
    # Outer 2px border
    draw.rectangle([0, 0, w - 1, h - 1], outline=(*PAL["obsidian"], 255), width=2)
    draw.rectangle([2, 2, w - 3, h - 3], outline=(*PAL["gunmetal"], 255), width=1)
    
    # Top/left highlight bevel
    draw.line([(4, 3), (w - 5, 3)], fill=(*PAL["pale_steel"], 255), width=1)
    draw.line([(3, 4), (3, h - 5)], fill=(*PAL["steel"], 255), width=1)
    # Bottom/right shadow bevel
    draw.line([(4, h - 4), (w - 5, h - 4)], fill=(*PAL["graphite"], 255), width=1)
    draw.line([(w - 4, 4), (w - 4, h - 5)], fill=(*PAL["graphite"], 255), width=1)
    
    # Top header bar slot (y=7..20, x=32..w-33)
    draw.rectangle([32, 7, w - 33, 20], fill=(*PAL["gunmetal"], 255), outline=(*PAL["obsidian"], 255))
    draw.line([(33, 8), (w - 34, 8)], fill=(*PAL["graphite"], 255))
    
    # Status indicator LEDs on header bar
    # LED 1: Power/Ready (Signal cyan)
    draw.rectangle([48, 11, 56, 17], fill=(*PAL["signal"], 255), outline=(*PAL["obsidian"], 255))
    draw.point((51, 13), fill=(*PAL["cloud_white"], 255))
    draw.point((52, 13), fill=(*PAL["cloud_white"], 255))
    # LED 2: Standby/Alert (Alert red)
    draw.rectangle([66, 11, 74, 17], fill=(*PAL["alert"], 255), outline=(*PAL["obsidian"], 255))
    draw.point((69, 13), fill=(*PAL["cloud_white"], 255))
    # LED 3: Telemetry (Lamp warm)
    draw.rectangle([84, 11, 92, 17], fill=(*PAL["lamp_warm"], 255), outline=(*PAL["obsidian"], 255))
    
    # Stamped channel markings / telemetry lines on header bar
    for x_pos in [120, 160, 200, 240, 720, 780, 840, 880]:
        draw.line([(x_pos, 11), (x_pos + 16, 11)], fill=(*PAL["antique_tin"], 255))
        draw.line([(x_pos, 15), (x_pos + 24, 15)], fill=(*PAL["slate"], 255))
        
    # Hex mounting bolts at regular intervals
    bolt_positions = [
        (14, 14), (w - 15, 14), (14, h - 15), (w - 15, h - 15),
        (240, 14), (480, 14), (720, 14),
        (240, h - 15), (480, h - 15), (720, h - 15),
        (14, 210), (w - 15, 210)
    ]
    for bx, by in bolt_positions:
        # 7x7 hex bolt
        draw.rectangle([bx - 3, by - 3, bx + 3, by + 3], fill=(*PAL["antique_tin"], 255), outline=(*PAL["obsidian"], 255))
        draw.point((bx - 2, by - 2), fill=(*PAL["pale_steel"], 255))
        draw.line([(bx - 2, by), (bx + 2, by)], fill=(*PAL["obsidian"], 255)) # slotted drive
        
    # Bottom control panel section (y=380..414)
    # Bevel line separating bottom control area
    draw.line([(4, 380), (w - 5, 380)], fill=(*PAL["graphite"], 255))
    draw.line([(4, 381), (w - 5, 381)], fill=(*PAL["steel"], 255))
    
    # Oscilloscope Dial 1 (TIME/DIV) at x=100, y=397
    draw.ellipse([88, 386, 112, 410], fill=(*PAL["steel"], 255), outline=(*PAL["obsidian"], 255))
    draw.ellipse([92, 390, 108, 406], fill=(*PAL["gunmetal"], 255), outline=(*PAL["antique_tin"], 255))
    draw.line([(100, 397), (100, 390)], fill=(*PAL["pale_steel"], 255), width=2) # knob notch
    # Dial 2 (VOLTS/DIV) at x=180, y=397
    draw.ellipse([168, 386, 192, 410], fill=(*PAL["steel"], 255), outline=(*PAL["obsidian"], 255))
    draw.ellipse([172, 390, 188, 406], fill=(*PAL["gunmetal"], 255), outline=(*PAL["antique_tin"], 255))
    draw.line([(180, 397), (185, 392)], fill=(*PAL["pale_steel"], 255), width=2)
    
    # Dual BNC Input Jacks at x=250, x=300
    for bnc_x in [260, 310]:
        draw.ellipse([bnc_x - 10, 388, bnc_x + 10, 408], fill=(*PAL["antique_tin"], 255), outline=(*PAL["obsidian"], 255))
        draw.ellipse([bnc_x - 6, 392, bnc_x + 6, 404], fill=(*PAL["gunmetal"], 255), outline=(*PAL["graphite"], 255))
        draw.ellipse([bnc_x - 2, 396, bnc_x + 2, 400], fill=(*PAL["pale_steel"], 255))
        
    # Cooling ventilation grille slots from x=370 to x=680
    for gx in range(370, 680, 8):
        draw.rectangle([gx, 388, gx + 4, 408], fill=(*PAL["obsidian"], 255))
        draw.line([(gx, 387), (gx + 4, 387)], fill=(*PAL["graphite"], 255))
        
    # Telemetry calibration test ports at x=730..880
    for px, col in [(740, "signal"), (770, "pale_steel"), (800, "alert")]:
        draw.rectangle([px - 6, 391, px + 6, 405], fill=(*PAL["gunmetal"], 255), outline=(*PAL["obsidian"], 255))
        draw.rectangle([px - 3, 394, px + 3, 402], fill=(*PAL[col], 255))
        draw.point((px, 398), fill=(*PAL["cloud_white"], 255))
        
    # CRT Screen Recessed Viewport
    # Screen inner boundary: x in [26, w - 27], y in [24, 375]
    vx1, vy1, vx2, vy2 = 26, 24, w - 27, 375
    
    # Outer recessed bevel around viewport
    draw.rectangle([vx1 - 3, vy1 - 3, vx2 + 3, vy2 + 3], outline=(*PAL["graphite"], 255), width=1)
    draw.rectangle([vx1 - 2, vy1 - 2, vx2 + 2, vy2 + 2], outline=(*PAL["gunmetal"], 255), width=1)
    draw.rectangle([vx1 - 1, vy1 - 1, vx2 + 1, vy2 + 1], outline=(*PAL["obsidian"], 255), width=1)
    
    # Top/left inner glass reflection glint
    draw.line([(vx1, vy1), (vx2 - 2, vy1)], fill=(*PAL["pale_steel"], 255))
    draw.line([(vx1, vy1), (vx1, vy2 - 2)], fill=(*PAL["pale_steel"], 255))
    draw.line([(vx1 + 1, vy1 + 1), (vx2 - 4, vy1 + 1)], fill=(*PAL["titanium"], 255))
    
    # Cut out transparent viewport (alpha=0)
    for y in range(vy1 + 2, vy2):
        for x in range(vx1 + 2, vx2):
            im.putpixel((x, y), (0, 0, 0, 0))
            
    # Rounded inner corners of the screen (3px radius chamfer)
    corners = [
        (vx1 + 2, vy1 + 2), (vx1 + 3, vy1 + 2), (vx1 + 2, vy1 + 3),
        (vx2 - 1, vy1 + 2), (vx2 - 2, vy1 + 2), (vx2 - 1, vy1 + 3),
        (vx1 + 2, vy2 - 1), (vx1 + 3, vy2 - 1), (vx1 + 2, vy2 - 2),
        (vx2 - 1, vy2 - 1), (vx2 - 2, vy2 - 1), (vx2 - 1, vy2 - 2),
    ]
    for cx, cy in corners:
        im.putpixel((cx, cy), (*PAL["obsidian"], 255))
        
    return quantize_to_palette(im, PAL)

# ==============================================================================
# 2. doc_reader_bg.png (920x560)
# Technical blueprint / document reader background with stamp box and margins
# ==============================================================================
def generate_doc_reader_bg():
    w, h = 920, 560
    im = Image.new("RGBA", (w, h), (*PAL["cool_slate"], 255))
    draw = ImageDraw.Draw(im)
    
    # Base paper sheet texture: subtle variations
    np.random.seed(42)
    # Add subtle aged paper grain using titanium & cool_slate
    arr = np.array(im)
    # Noise mask
    noise = np.random.rand(h, w)
    grain_mask = noise > 0.985
    arr[grain_mask, 0] = PAL["titanium"][0]
    arr[grain_mask, 1] = PAL["titanium"][1]
    arr[grain_mask, 2] = PAL["titanium"][2]
    
    im = Image.fromarray(arr, "RGBA")
    draw = ImageDraw.Draw(im)
    
    # Technical border margin
    # Outer double line
    draw.rectangle([14, 14, w - 15, h - 15], outline=(*PAL["gunmetal"], 255), width=2)
    draw.rectangle([18, 18, w - 19, h - 19], outline=(*PAL["storm_gray"], 255), width=1)
    
    # Left binder filing punch holes (3 holes at y=100, 280, 460)
    for py in [100, 280, 460]:
        px = 38
        draw.ellipse([px - 9, py - 9, px + 9, py + 9], fill=(*PAL["antique_tin"], 255), outline=(*PAL["gunmetal"], 255))
        draw.ellipse([px - 7, py - 7, px + 7, py + 7], fill=(*PAL["obsidian"], 255))
        draw.line([(px - 7, py - 7), (px + 7, py + 7)], fill=(*PAL["graphite"], 255))
        
    # Vertical line separating binder margin from content
    draw.line([(62, 18), (62, h - 19)], fill=(*PAL["storm_gray"], 255), width=2)
    
    # Header zone (y=18..84)
    draw.line([(62, 84), (w - 19, 84)], fill=(*PAL["gunmetal"], 255), width=2)
    draw.line([(62, 88), (w - 19, 88)], fill=(*PAL["storm_gray"], 255), width=1)
    
    # Header sub-boxes
    # Box 1: Ministry / Dept header
    draw.line([(320, 18), (320, 84)], fill=(*PAL["storm_gray"], 255))
    draw.rectangle([68, 24, 314, 78], outline=(*PAL["slate"], 255))
    # Blueprint grid inside header box
    for gx in range(78, 310, 16):
        draw.line([(gx, 24), (gx, 78)], fill=(*PAL["pale_steel"], 255))
    for gy in range(34, 78, 12):
        draw.line([(68, gy), (314, gy)], fill=(*PAL["pale_steel"], 255))
        
    # Box 2: Document Index / Reg Number
    draw.line([(580, 18), (580, 84)], fill=(*PAL["storm_gray"], 255))
    draw.rectangle([328, 24, 572, 78], outline=(*PAL["slate"], 255))
    # Simulated form lines
    draw.line([(336, 42), (564, 42)], fill=(*PAL["antique_tin"], 255))
    draw.line([(336, 62), (564, 62)], fill=(*PAL["antique_tin"], 255))
    
    # Box 3: Security classification hatch zone (x=580..w-19)
    draw.rectangle([588, 24, w - 26, 78], outline=(*PAL["gunmetal"], 255))
    for hx in range(588, w - 26, 8):
        draw.line([(hx, 24), (min(hx + 30, w - 26), 78)], fill=(*PAL["storm_gray"], 255))
        
    # Main Body Area (y=92..430)
    # Faint engineering grid points (dots every 20px)
    for gy in range(104, 430, 20):
        for gx in range(80, w - 40, 20):
            draw.point((gx, gy), fill=(*PAL["pale_steel"], 255))
            
    # Technical Schematic Blueprint Drawing Frame (left column: x=76..480, y=104..420)
    draw.rectangle([76, 104, 480, 420], outline=(*PAL["gunmetal"], 255), width=2)
    draw.rectangle([80, 108, 476, 416], outline=(*PAL["slate"], 255), width=1)
    
    # Schematic Drawing: Robot Torso / Service Bay Orthogonal Blueprint
    # Centerline
    draw.line([(278, 116), (278, 408)], fill=(*PAL["signal"], 255)) # axis
    # Outer hull silhouette
    draw.polygon([
        (210, 140), (346, 140), # shoulders
        (370, 200), (356, 320), # torso sides
        (330, 390), (226, 390), # pelvis/mount
        (200, 320), (186, 200)
    ], outline=(*PAL["gunmetal"], 255), fill=(*PAL["titanium"], 255))
    # Chest maintenance hatch cutaway
    draw.rectangle([236, 190, 320, 270], fill=(*PAL["cool_slate"], 255), outline=(*PAL["gunmetal"], 255), width=2)
    # Contact terminals & wire routing
    draw.rectangle([250, 206, 306, 254], outline=(*PAL["storm_gray"], 255))
    for ty in [216, 228, 240]:
        draw.ellipse([258, ty - 2, 264, ty + 2], fill=(*PAL["antique_tin"], 255), outline=(*PAL["obsidian"], 255))
        draw.ellipse([292, ty - 2, 298, ty + 2], fill=(*PAL["antique_tin"], 255), outline=(*PAL["obsidian"], 255))
        draw.line([(264, ty), (292, ty)], fill=(*PAL["alert"], 255)) # circuit trace
        
    # Dimension leader lines and callouts
    draw.line([(160, 140), (210, 140)], fill=(*PAL["slate"], 255))
    draw.line([(160, 134), (160, 146)], fill=(*PAL["slate"], 255))
    draw.line([(346, 140), (410, 140)], fill=(*PAL["slate"], 255))
    draw.line([(410, 134), (410, 146)], fill=(*PAL["slate"], 255))
    draw.line([(278, 270), (278, 300), (310, 330)], fill=(*PAL["signal"], 255)) # pointer leader
    draw.ellipse([308, 328, 312, 332], fill=(*PAL["signal"], 255))
    
    # Right Column: Procedural Service Steps Table (x=496..896, y=104..420)
    draw.rectangle([496, 104, 896, 420], outline=(*PAL["gunmetal"], 255), width=2)
    draw.line([(496, 136), (896, 136)], fill=(*PAL["gunmetal"], 255), width=2)
    # Table header bar
    draw.rectangle([498, 106, 894, 134], fill=(*PAL["titanium"], 255))
    draw.line([(550, 104), (550, 420)], fill=(*PAL["storm_gray"], 255)) # step # col
    draw.line([(760, 104), (760, 420)], fill=(*PAL["storm_gray"], 255)) # status col
    
    # Table rows
    for ry in range(168, 420, 32):
        draw.line([(496, ry), (896, ry)], fill=(*PAL["storm_gray"], 255))
        # Checkbox
        draw.rectangle([514, ry - 22, 532, ry - 8], outline=(*PAL["gunmetal"], 255))
        # Simulated text lines
        draw.line([(566, ry - 18), (730, ry - 18)], fill=(*PAL["antique_tin"], 255), width=2)
        draw.line([(566, ry - 10), (680, ry - 10)], fill=(*PAL["slate"], 255), width=1)
        # Spec param bars
        draw.line([(776, ry - 15), (876, ry - 15)], fill=(*PAL["storm_gray"], 255), width=2)
        
    # Standard Technical Title / Stamp Block (ГОСТ/DIN Title Block) at bottom right
    # (x=496..896, y=434..540)
    bx1, by1, bx2, by2 = 496, 434, 896, 540
    draw.rectangle([bx1, by1, bx2, by2], outline=(*PAL["gunmetal"], 255), width=2)
    # Horizontal divisions
    draw.line([(bx1, by1 + 26), (bx2, by1 + 26)], fill=(*PAL["gunmetal"], 255))
    draw.line([(bx1, by1 + 52), (bx2, by1 + 52)], fill=(*PAL["gunmetal"], 255))
    draw.line([(bx1, by1 + 78), (bx2, by1 + 78)], fill=(*PAL["gunmetal"], 255))
    # Vertical divisions
    draw.line([(bx1 + 100, by1), (bx1 + 100, by2)], fill=(*PAL["gunmetal"], 255))
    draw.line([(bx1 + 200, by1), (bx1 + 200, by2)], fill=(*PAL["gunmetal"], 255))
    draw.line([(bx1 + 300, by1), (bx1 + 300, by2)], fill=(*PAL["gunmetal"], 255))
    # Title block cell labels simulation
    for cy in [by1 + 10, by1 + 36, by1 + 62, by1 + 88]:
        draw.line([(bx1 + 10, cy), (bx1 + 80, cy)], fill=(*PAL["slate"], 255), width=1)
        draw.line([(bx1 + 110, cy), (bx1 + 180, cy)], fill=(*PAL["storm_gray"], 255), width=1)
        
    # Free stamp landing area on the right half of the stamp box
    # Reserved clean zone for stamp_ok / stamp_fail
    draw.rectangle([bx1 + 204, by1 + 4, bx2 - 4, by2 - 4], fill=(*PAL["cool_slate"], 255))
    draw.rectangle([bx1 + 208, by1 + 8, bx2 - 8, by2 - 8], outline=(*PAL["slate"], 255))
    
    # Narrative wear & tear details
    # Horizontal document fold line at y=280
    draw.line([(18, 280), (w - 19, 280)], fill=(*PAL["pale_steel"], 255))
    draw.line([(18, 281), (w - 19, 281)], fill=(*PAL["slate"], 255))
    
    # Coffee mug ring stain at bottom left (around x=240, y=485)
    for angle in np.linspace(0, 2 * np.pi, 120):
        r = 34 + np.sin(angle * 7) * 1.5
        rx = int(240 + r * np.cos(angle))
        ry = int(485 + r * np.sin(angle))
        if 0 <= rx < w and 0 <= ry < h:
            draw.point((rx, ry), fill=(*PAL["rust"], 255))
            if np.sin(angle * 3) > 0.3:
                draw.point((rx + 1, ry), fill=(*PAL["lamp_warm"], 255))
                
    # Oil smudge mark at top right corner
    for ox in range(w - 60, w - 30):
        for oy in range(30, 55):
            if (ox - (w - 45))**2 + (oy - 42)**2 < 120:
                if (ox + oy) % 3 == 0:
                    draw.point((ox, oy), fill=(*PAL["rust"], 255))
                    
    return quantize_to_palette(im, PAL)

# ==============================================================================
# 3. card_tab.png (48x24)
# Card index drawer folder tab
# ==============================================================================
def generate_card_tab():
    w, h = 48, 24
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # Upper Tab tongue: x=6..41, y=2..16
    # Chamfered top corners (cut at (6,2), (7,2), (40,2), (41,2))
    # Tab body
    draw.polygon([
        (8, 2), (39, 2),
        (42, 6), (42, 16),
        (5, 16), (5, 6)
    ], fill=(*PAL["signal"], 255), outline=(*PAL["gunmetal"], 255))
    
    # Top highlight
    draw.line([(9, 3), (38, 3)], fill=(*PAL["cloud_white"], 255))
    
    # Tab Label Slot Insert (Cool Slate paper window)
    draw.rectangle([9, 5, 38, 14], fill=(*PAL["cool_slate"], 255), outline=(*PAL["storm_gray"], 255))
    draw.line([(12, 9), (35, 9)], fill=(*PAL["gunmetal"], 255)) # center index line
    draw.point((10, 6), fill=(*PAL["pale_steel"], 255))
    
    # Lower Card Shoulder: x=0..47, y=16..23
    draw.rectangle([0, 16, 47, 23], fill=(*PAL["cool_slate"], 255), outline=(*PAL["gunmetal"], 255))
    # Top card rim highlight
    draw.line([(0, 16), (47, 16)], fill=(*PAL["pale_steel"], 255))
    draw.line([(0, 17), (47, 17)], fill=(*PAL["gunmetal"], 255))
    # Card vertical fibers
    for fx in [10, 24, 38]:
        draw.line([(fx, 18), (fx, 22)], fill=(*PAL["titanium"], 255))
        
    return quantize_to_palette(im, PAL)

# ==============================================================================
# 4. glitch_strip.png (256x16)
# CRT visual interference glitch strip
# ==============================================================================
def generate_glitch_strip():
    w, h = 256, 16
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # Block 1: Left chromatic aberration burst (x=0..36)
    draw.rectangle([0, 2, 28, 5], fill=(*PAL["alert"], 255))
    draw.rectangle([4, 6, 36, 9], fill=(*PAL["signal"], 255))
    draw.rectangle([12, 10, 30, 13], fill=(*PAL["obsidian"], 255))
    draw.line([(0, 4), (25, 4)], fill=(*PAL["cloud_white"], 255))
    
    # Block 2: Interleaved scanline corruption (x=45..85)
    for y in range(1, 15, 2):
        draw.line([(45 + (y * 3) % 10, y), (85 - (y * 2) % 8, y)], fill=(*PAL["pale_steel"], 255))
        draw.line([(48 + (y * 3) % 10, y + 1), (82 - (y * 2) % 8, y + 1)], fill=(*PAL["storm_gray"], 255))
        
    # Block 3: Signal dropout block (x=95..140)
    draw.rectangle([95, 3, 135, 7], fill=(*PAL["obsidian"], 255))
    draw.rectangle([100, 8, 140, 12], fill=(*PAL["gunmetal"], 255))
    draw.line([(102, 5), (128, 5)], fill=(*PAL["alert"], 255))
    draw.line([(98, 10), (135, 10)], fill=(*PAL["signal"], 255))
    
    # Block 4: Phosphor beam overdrive bright streak (x=148..205)
    draw.rectangle([148, 4, 205, 8], fill=(*PAL["cloud_white"], 255))
    draw.line([(145, 3), (208, 3)], fill=(*PAL["signal"], 255))
    draw.line([(150, 9), (202, 9)], fill=(*PAL["alert"], 255))
    draw.rectangle([165, 9, 195, 13], fill=(*PAL["pale_steel"], 255))
    
    # Block 5: Digital noise scatter (x=215..255)
    for x in range(215, 255, 3):
        for y in range(2, 14, 3):
            col = "alert" if (x + y) % 5 == 0 else ("signal" if (x * y) % 3 == 0 else "cloud_white")
            draw.point((x, y), fill=(*PAL[col], 255))
            draw.point((x + 1, y), fill=(*PAL["obsidian"], 255))
            
    return quantize_to_palette(im, PAL)

# ==============================================================================
# 5. doc_folder.png (64x64)
# Maintenance document folder icon
# ==============================================================================
def generate_doc_folder():
    w, h = 64, 64
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # Back flap and top tab (y=10..18, x=10..32)
    draw.polygon([(10, 14), (14, 10), (30, 10), (34, 14), (54, 14), (54, 20), (10, 20)],
                 fill=(*PAL["storm_gray"], 255), outline=(*PAL["gunmetal"], 255))
    draw.line([(15, 11), (29, 11)], fill=(*PAL["pale_steel"], 255))
    
    # Main folder front body (y=18..54, x=8..56)
    # Chamfered corners
    draw.polygon([
        (10, 18), (54, 18),
        (56, 20), (56, 52),
        (54, 54), (10, 54),
        (8, 52), (8, 20)
    ], fill=(*PAL["steel"], 255), outline=(*PAL["gunmetal"], 255))
    
    # Top highlight bevel
    draw.line([(10, 19), (53, 19)], fill=(*PAL["pale_steel"], 255))
    # Bottom shadow
    draw.line([(10, 53), (53, 53)], fill=(*PAL["graphite"], 255))
    
    # Left spine binding (x=8..15)
    draw.rectangle([8, 18, 15, 54], fill=(*PAL["storm_gray"], 255), outline=(*PAL["gunmetal"], 255))
    # Binding rivets (Antique Tin with Pale Steel glint)
    for ry in [26, 46]:
        draw.ellipse([10, ry - 2, 13, ry + 2], fill=(*PAL["antique_tin"], 255), outline=(*PAL["obsidian"], 255))
        draw.point((11, ry - 1), fill=(*PAL["pale_steel"], 255))
        
    # Service Label Sticker (x=20..50, y=26..44)
    draw.rectangle([20, 26, 50, 44], fill=(*PAL["cool_slate"], 255), outline=(*PAL["gunmetal"], 255))
    # Simulated technical text lines
    draw.line([(24, 30), (46, 30)], fill=(*PAL["gunmetal"], 255), width=2)
    draw.line([(24, 35), (42, 35)], fill=(*PAL["storm_gray"], 255), width=1)
    draw.line([(24, 39), (38, 39)], fill=(*PAL["slate"], 255), width=1)
    
    # Top-right classification corner flash (Alert red triangle)
    draw.polygon([(44, 19), (53, 19), (53, 28)], fill=(*PAL["alert"], 255), outline=(*PAL["obsidian"], 255))
    draw.point((50, 22), fill=(*PAL["cloud_white"], 255))
    
    # Bottom drop shadow
    draw.line([(10, 55), (54, 55)], fill=(*PAL["obsidian"], 255))
    draw.line([(12, 56), (52, 56)], fill=(*PAL["gunmetal"], 255))
    
    return quantize_to_palette(im, PAL)

# ==============================================================================
# 6. diag_needle.png (32x64)
# Calibration / diagnostic gauge needle
# ==============================================================================
def generate_diag_needle():
    w, h = 32, 64
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # Pivot center is at x=16, y=52
    cx, cy = 16, 52
    
    # Needle blade shank: from y=45 up to tip at y=4
    # Polygon with knife-edge taper
    blade_poly = [
        (cx - 3, cy - 7), # left base at y=45
        (cx - 1, 8),      # left upper shank
        (cx, 4),          # pointer sharp tip at y=4
        (cx + 1, 8),      # right upper shank
        (cx + 3, cy - 7)  # right base at y=45
    ]
    # Draw dark outline
    draw.polygon(blade_poly, fill=(*PAL["gunmetal"], 255), outline=(*PAL["obsidian"], 255))
    
    # Lower blade section (y=22..45) in Pale Steel / Steel
    draw.polygon([(cx - 2, cy - 7), (cx - 1, 22), (cx + 1, 22), (cx + 2, cy - 7)], fill=(*PAL["steel"], 255))
    draw.line([(cx - 1, cy - 7), (cx, 22)], fill=(*PAL["pale_steel"], 255))
    
    # Upper pointer indicator tip (y=4..21) in high-visibility Alert red
    draw.polygon([(cx - 1, 21), (cx - 1, 8), (cx, 4), (cx + 1, 8), (cx + 1, 21)], fill=(*PAL["alert"], 255))
    # Center spine ridge glint (Cloud White)
    draw.line([(cx, 5), (cx, 14)], fill=(*PAL["cloud_white"], 255))
    draw.line([(cx, 15), (cx, 21)], fill=(*PAL["pale_steel"], 255))
    
    # Circular Pivot Hub (x=16, y=52, radius 7px)
    draw.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=(*PAL["antique_tin"], 255), outline=(*PAL["obsidian"], 255))
    # Inner screw head (radius 4px)
    draw.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(*PAL["steel"], 255), outline=(*PAL["gunmetal"], 255))
    # Glint & Slotted drive
    draw.point((cx - 2, cy - 2), fill=(*PAL["pale_steel"], 255))
    draw.line([(cx - 2, cy), (cx + 2, cy)], fill=(*PAL["obsidian"], 255))
    
    # Counterbalance tail below hub (y=59..62)
    draw.polygon([(cx - 2, cy + 7), (cx - 1, 62), (cx + 1, 62), (cx + 2, cy + 7)],
                 fill=(*PAL["gunmetal"], 255), outline=(*PAL["obsidian"], 255))
                 
    return quantize_to_palette(im, PAL)

# ==============================================================================
# 7. keyart.png (1280x720)
# Signature key art of 'Do Not Wake'
# ==============================================================================
def generate_keyart():
    # Source image: harmonized composite
    source_path = os.path.join("docs", "preview_harmonized.png")
    if not os.path.exists(source_path):
        source_path = os.path.join("docs", "preview_operating_room_composited.png")
    
    im = Image.open(source_path).convert("RGBA")
    
    # Add crisp focal details in project palette:
    draw = ImageDraw.Draw(im)
    # 1. Visor eye glint on robot: Signal / Cloud White pinpoint
    # Head center is at x=640, y=168
    draw.point((639, 168), fill=(*PAL["signal"], 255))
    draw.point((640, 168), fill=(*PAL["cloud_white"], 255))
    draw.point((641, 168), fill=(*PAL["signal"], 255))
    
    # 2. CRT Monitor status LED accents on left/right console banks
    # Left monitor LEDs
    draw.point((186, 240), fill=(*PAL["alert"], 255))
    draw.point((187, 240), fill=(*PAL["alert"], 255))
    draw.point((210, 240), fill=(*PAL["signal"], 255))
    # Right monitor LEDs
    draw.point((1090, 240), fill=(*PAL["signal"], 255))
    draw.point((1091, 240), fill=(*PAL["signal"], 255))
    draw.point((1115, 240), fill=(*PAL["alert"], 255))
    
    # 3. Steel harness buckle highlights
    for by in [264, 380, 490]:
        draw.point((580, by), fill=(*PAL["pale_steel"], 255))
        draw.point((700, by), fill=(*PAL["pale_steel"], 255))
        
    # Quantize strictly to 15 colors with Dither.NONE
    q = quantize_to_palette(im, PAL)
    return q

def main():
    print("Generating assets...")
    
    # 1. diag_frame.png
    p1 = os.path.join("assets", "sprites", "ui", "diag_frame.png")
    im1 = generate_diag_frame()
    im1.save(p1)
    print(f"Saved {p1} {im1.size}")
    
    # 2. doc_reader_bg.png
    p2 = os.path.join("assets", "sprites", "ui", "doc_reader_bg.png")
    im2 = generate_doc_reader_bg()
    im2.save(p2)
    print(f"Saved {p2} {im2.size}")
    
    # 3. card_tab.png
    p3 = os.path.join("assets", "sprites", "ui", "card_tab.png")
    im3 = generate_card_tab()
    im3.save(p3)
    print(f"Saved {p3} {im3.size}")
    
    # 4. glitch_strip.png
    p4 = os.path.join("assets", "sprites", "ui", "glitch_strip.png")
    im4 = generate_glitch_strip()
    im4.save(p4)
    print(f"Saved {p4} {im4.size}")
    
    # 5. doc_folder.png
    p5 = os.path.join("assets", "sprites", "ui", "doc_folder.png")
    im5 = generate_doc_folder()
    im5.save(p5)
    print(f"Saved {p5} {im5.size}")
    
    # 6. diag_needle.png
    p6 = os.path.join("assets", "sprites", "ui", "diag_needle.png")
    im6 = generate_diag_needle()
    im6.save(p6)
    print(f"Saved {p6} {im6.size}")
    
    # 7. keyart.png & keyart_thumb10pct.png
    p7 = os.path.join("docs", "keyart.png")
    im7 = generate_keyart()
    im7.save(p7)
    print(f"Saved {p7} {im7.size}")
    
    thumb = im7.resize((128, 72), Image.Resampling.NEAREST)
    thumb_q = quantize_to_palette(thumb, PAL)
    p_thumb = os.path.join("docs", "keyart_thumb10pct.png")
    thumb_q.save(p_thumb)
    print(f"Saved {p_thumb} {thumb_q.size}")
    
    print("\nAll assets generated successfully!")

if __name__ == "__main__":
    main()
