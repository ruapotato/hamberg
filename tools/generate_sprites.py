#!/usr/bin/env python3
"""Generate multi-angle character sprite sheets using aalib for ASCII art look.

Pipeline (from The-Mount):
  1. Draw 3D silhouette as a grayscale image (full body composite)
  2. Convert through aalib for real AA-style character mapping
  3. Re-render the AA text with phosphor colors + glow

Outputs front/back/left/right PNGs for each character.

Usage:
    python3 tools/generate_sprites.py
    python3 tools/generate_sprites.py --characters mage zombie_walker deer
"""

import argparse
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import aalib

SCRIPT_DIR = Path(__file__).parent
OUT_BASE = SCRIPT_DIR.parent / "assets" / "sprites" / "characters"

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
RENDER_FONT_SIZE = 10
CELL_W = 6
CELL_H = 11


def get_font():
    return ImageFont.truetype(FONT_PATH, RENDER_FONT_SIZE)


# ---------------------------------------------------------------------------
# Palettes
# ---------------------------------------------------------------------------

PALETTES = {
    "mage": {
        "fg": (130, 120, 210),
        "hi": (200, 190, 255),
        "glow": (120, 110, 200, 45),
    },
    "warrior": {
        "fg": (220, 170, 90),
        "hi": (255, 220, 150),
        "glow": (210, 160, 80, 45),
    },
    "zombie_walker": {
        "fg": (100, 190, 100),
        "hi": (160, 240, 160),
        "glow": (90, 180, 90, 45),
    },
    "zombie_runner": {
        "fg": (210, 90, 90),
        "hi": (255, 150, 150),
        "glow": (200, 80, 80, 45),
    },
    "zombie_brute": {
        "fg": (150, 150, 155),
        "hi": (210, 210, 215),
        "glow": (140, 140, 145, 45),
    },
    "deer": {
        "fg": (185, 140, 90),
        "hi": (235, 200, 150),
        "glow": (175, 130, 80, 45),
    },
    "pig": {
        "fg": (220, 160, 170),
        "hi": (255, 210, 220),
        "glow": (210, 150, 160, 45),
    },
    "sheep": {
        "fg": (230, 225, 210),
        "hi": (255, 252, 245),
        "glow": (220, 215, 200, 45),
    },
    "alice": {
        "fg": (195, 185, 245),
        "hi": (240, 230, 255),
        "glow": (180, 170, 240, 45),
    },
    "skeleton": {
        "fg": (225, 205, 165),
        "hi": (255, 240, 200),
        "glow": (215, 195, 150, 45),
    },
}


# ---------------------------------------------------------------------------
# aalib pipeline (from The-Mount)
# ---------------------------------------------------------------------------

def image_to_aalib(img: Image.Image, aa_width: int, aa_height: int) -> list[str]:
    """Convert a PIL image to ASCII art lines via aalib."""
    screen = aalib.AsciiScreen(width=aa_width, height=aa_height)
    gray = img.convert("L")
    vw, vh = screen.virtual_size
    gray = gray.resize((vw, vh), Image.LANCZOS)
    screen.put_image((0, 0), gray)
    text = screen.render()
    return text.split("\n")


def render_aa_text(lines: list[str], palette: dict, scale: int = 3) -> Image.Image:
    """Render aalib text output with phosphor coloring and glow."""
    font = get_font()
    max_cols = max(len(line) for line in lines) if lines else 1
    rows = len(lines)

    w = max_cols * CELL_W + 4
    h = rows * CELL_H + 4

    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)

    fg = palette["fg"]
    hi = palette["hi"]
    glow_color = palette["glow"]

    density_map = " .,:;!|/\\(){}[]<>+=-_~?#@$%&*"
    max_density = len(density_map) - 1

    for row_i, line in enumerate(lines):
        for col_i, ch in enumerate(line):
            if ch == " ":
                continue
            x = col_i * CELL_W + 2
            y = row_i * CELL_H + 2

            if ch in density_map:
                brightness = density_map.index(ch) / max_density
            else:
                brightness = 0.6

            r = int(fg[0] + (hi[0] - fg[0]) * brightness)
            g = int(fg[1] + (hi[1] - fg[1]) * brightness)
            b = int(fg[2] + (hi[2] - fg[2]) * brightness)
            color = (r, g, b, 255)

            draw.text((x, y), ch, fill=color, font=font)
            glow_draw.text((x, y), ch, fill=glow_color, font=font)

    for _ in range(3):
        glow = glow.filter(ImageFilter.GaussianBlur(radius=1.5))

    result = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    result = Image.alpha_composite(result, glow)
    result = Image.alpha_composite(result, img)

    result = result.resize((w * scale, h * scale), Image.NEAREST)
    return result


# ---------------------------------------------------------------------------
# 3D shading helpers
# ---------------------------------------------------------------------------

def shade_ellipse(img: Image.Image, cx: int, cy: int, rx: int, ry: int,
                  base_val: int = 160, light_bias: float = 0.3):
    """Fill an elliptical region with left-lit 3D shading."""
    for y in range(max(0, cy - ry), min(img.height, cy + ry + 1)):
        for x in range(max(0, cx - rx), min(img.width, cx + rx + 1)):
            dx = (x - cx) / max(rx, 1)
            dy = (y - cy) / max(ry, 1)
            dist = (dx * dx + dy * dy) ** 0.5
            if dist < 1.0:
                shade = 1.0 - dist * 0.3
                light = max(0, -dx * light_bias + 0.5)
                val = int((shade * 0.5 + light * 0.5) * base_val + 30)
                img.putpixel((x, y), min(255, max(0, val)))


def shade_rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int,
               base_val: int = 160):
    """Fill a rect region with left-lit cylindrical shading."""
    cx = (x0 + x1) // 2
    hw = (x1 - x0) / 2
    for y in range(max(0, y0), min(img.height, y1)):
        for x in range(max(0, x0), min(img.width, x1)):
            dx = abs(x - cx) / max(hw, 1)
            shade = int((1.0 - dx * dx) * base_val + 40)
            if x < cx:
                shade = min(255, shade + 15)
            else:
                shade = max(0, shade - 15)
            img.putpixel((x, y), max(0, min(255, shade)))


def shade_trapezoid(img: Image.Image, top_cx: int, top_y: int, top_hw: int,
                    bot_cx: int, bot_y: int, bot_hw: int, base_val: int = 160):
    """Fill a trapezoid with left-lit cylindrical shading."""
    for y in range(max(0, top_y), min(img.height, bot_y)):
        t = (y - top_y) / max(bot_y - top_y, 1)
        cx = int(top_cx + (bot_cx - top_cx) * t)
        hw = top_hw + (bot_hw - top_hw) * t
        for x in range(max(0, int(cx - hw)), min(img.width, int(cx + hw))):
            dx = abs(x - cx) / max(hw, 1)
            shade = int((1.0 - dx * dx) * base_val + 40)
            if x < cx:
                shade = min(255, shade + 15)
            else:
                shade = max(0, shade - 15)
            img.putpixel((x, y), max(0, min(255, shade)))


# ---------------------------------------------------------------------------
# Humanoid silhouette drawing — full body composites
# ---------------------------------------------------------------------------

def draw_humanoid_front(w: int, h: int, *,
                        head_ratio: float = 0.2,
                        shoulder_width: float = 0.5,
                        waist_width: float = 0.35,
                        has_eyes: bool = True,
                        is_skeleton: bool = False,
                        hat: str = "none",
                        weapon: str = "none",
                        bulk: float = 1.0) -> Image.Image:
    """Draw a front-facing full body humanoid silhouette."""
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)
    cx = w // 2

    # Proportions
    head_h = int(h * head_ratio)
    head_r = int(head_h * 0.45)
    neck_y = head_h
    torso_top = neck_y + 2
    torso_bot = int(h * 0.55)
    leg_top = torso_bot
    leg_bot = h - 6
    foot_h = 5

    sw = int(w * shoulder_width * bulk)
    ww = int(w * waist_width * bulk)

    # Hat
    if hat == "wizard":
        # Pointy wizard hat
        hat_base_y = int(h * head_ratio * 0.25)
        hat_tip_y = 0
        hat_hw = head_r + 3
        for y in range(hat_tip_y, hat_base_y):
            t = y / max(hat_base_y, 1)
            cur_hw = int(hat_hw * t * 0.6)
            for x in range(cx - cur_hw, cx + cur_hw + 1):
                if 0 <= x < w:
                    shade = 80 + int(40 * (1 - abs(x - cx) / max(cur_hw, 1)))
                    img.putpixel((x, y), shade)
        # Brim
        brim_y = hat_base_y
        brim_hw = head_r + 6
        for x in range(cx - brim_hw, cx + brim_hw + 1):
            if 0 <= x < w:
                img.putpixel((x, brim_y), 100)
                if brim_y + 1 < h:
                    img.putpixel((x, brim_y + 1), 80)

    elif hat == "helmet":
        # Rounded helmet
        helm_cy = int(h * head_ratio * 0.3)
        helm_rx = head_r + 4
        helm_ry = int(head_r * 0.7)
        shade_ellipse(img, cx, helm_cy, helm_rx, helm_ry, base_val=120)

    # Head
    head_cy = int(head_h * 0.55)
    shade_ellipse(img, cx, head_cy, head_r, int(head_r * 1.1), base_val=180)

    # Eyes
    if has_eyes and not is_skeleton:
        eye_y = head_cy - 1
        eye_spread = head_r // 3
        er = max(1, head_r // 8)
        draw.ellipse([cx - eye_spread - er, eye_y - er,
                      cx - eye_spread + er, eye_y + er], fill=30)
        draw.ellipse([cx + eye_spread - er, eye_y - er,
                      cx + eye_spread + er, eye_y + er], fill=30)

    if is_skeleton:
        eye_y = head_cy - 1
        eye_spread = head_r // 3
        er = max(1, head_r // 6)
        draw.ellipse([cx - eye_spread - er, eye_y - er,
                      cx - eye_spread + er, eye_y + er], fill=20)
        draw.ellipse([cx + eye_spread - er, eye_y - er,
                      cx + eye_spread + er, eye_y + er], fill=20)
        # Nose hole
        draw.polygon([(cx - 1, head_cy + 2), (cx + 1, head_cy + 2),
                       (cx, head_cy + 4)], fill=30)
        # Teeth
        teeth_y = head_cy + head_r // 3
        for tx in range(cx - head_r // 3, cx + head_r // 3, 3):
            draw.rectangle([tx, teeth_y, tx + 1, teeth_y + 2], fill=200)

    # Neck
    neck_hw = max(2, int(w * 0.06 * bulk))
    shade_rect(img, cx - neck_hw, neck_y - 1, cx + neck_hw, torso_top + 2, base_val=140)

    # Torso
    shade_trapezoid(img, cx, torso_top, sw // 2, cx, torso_bot, ww // 2, base_val=170)

    # Arms
    arm_w = max(3, int(w * 0.07 * bulk))
    arm_top = torso_top + 2
    arm_bot = torso_bot + int(h * 0.08)
    # Left arm
    shade_rect(img, cx - sw // 2 - arm_w, arm_top, cx - sw // 2 + 1, arm_bot, base_val=150)
    # Right arm
    shade_rect(img, cx + sw // 2 - 1, arm_top, cx + sw // 2 + arm_w, arm_bot, base_val=150)

    # Hands
    hand_r = max(2, arm_w)
    hand_y = arm_bot + hand_r
    shade_ellipse(img, cx - sw // 2 - arm_w // 2, hand_y, hand_r, hand_r, base_val=150)
    shade_ellipse(img, cx + sw // 2 + arm_w // 2, hand_y, hand_r, hand_r, base_val=150)

    # Weapon
    if weapon == "staff":
        staff_x = cx + sw // 2 + arm_w + 2
        for y in range(arm_top - 5, leg_bot):
            if 0 <= staff_x < w and 0 <= y < h:
                img.putpixel((staff_x, y), 130)
                if staff_x + 1 < w:
                    img.putpixel((staff_x + 1, y), 100)
        # Orb at top
        shade_ellipse(img, staff_x, arm_top - 8, 3, 3, base_val=220)

    elif weapon == "sword":
        sword_x = cx + sw // 2 + arm_w + 2
        for y in range(arm_top, arm_bot + 10):
            if 0 <= sword_x < w and 0 <= y < h:
                img.putpixel((sword_x, y), 200)
        # Crossguard
        guard_y = arm_bot - 2
        for x in range(sword_x - 3, sword_x + 4):
            if 0 <= x < w and 0 <= guard_y < h:
                img.putpixel((x, guard_y), 180)

    # Legs
    leg_hw = max(3, int(w * 0.08 * bulk))
    leg_gap = max(1, int(w * 0.03))
    # Left leg
    shade_rect(img, cx - leg_gap - leg_hw * 2, leg_top, cx - leg_gap, leg_bot, base_val=150)
    # Right leg
    shade_rect(img, cx + leg_gap, leg_top, cx + leg_gap + leg_hw * 2, leg_bot, base_val=150)

    # Feet
    foot_hw = leg_hw + 2
    for leg_cx in [cx - leg_gap - leg_hw, cx + leg_gap + leg_hw]:
        shade_ellipse(img, leg_cx, leg_bot + 2, foot_hw, 3, base_val=130)

    return img


def draw_humanoid_back(w: int, h: int, **kwargs) -> Image.Image:
    """Draw a back-facing humanoid — same shape, no face details."""
    kw = dict(kwargs)
    kw["has_eyes"] = False
    kw["is_skeleton"] = False
    return draw_humanoid_front(w, h, **kw)


def draw_humanoid_side(w: int, h: int, *,
                       head_ratio: float = 0.2,
                       body_width: float = 0.35,
                       hat: str = "none",
                       weapon: str = "none",
                       bulk: float = 1.0,
                       is_skeleton: bool = False) -> Image.Image:
    """Draw a side-profile humanoid silhouette (facing left)."""
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)

    # Key positions
    head_h = int(h * head_ratio)
    head_r = int(head_h * 0.42)
    head_cx = w // 2
    head_cy = int(head_h * 0.55)

    neck_y = head_h
    torso_top = neck_y + 2
    torso_bot = int(h * 0.55)
    leg_bot = h - 6

    body_hw = int(w * body_width * bulk * 0.5)

    # Hat
    if hat == "wizard":
        hat_base_y = int(head_h * 0.25)
        for y in range(0, hat_base_y):
            t = y / max(hat_base_y, 1)
            cur_hw = int(head_r * t * 0.5)
            for x in range(head_cx - cur_hw, head_cx + cur_hw + 1):
                if 0 <= x < w:
                    img.putpixel((x, y), 80)
        # Brim
        brim_hw = head_r + 4
        for x in range(head_cx - brim_hw, head_cx + brim_hw // 2 + 1):
            if 0 <= x < w and hat_base_y < h:
                img.putpixel((x, hat_base_y), 100)
    elif hat == "helmet":
        helm_cy = int(head_h * 0.35)
        shade_ellipse(img, head_cx, helm_cy, head_r + 2, int(head_r * 0.65), base_val=120)

    # Head (slightly forward)
    shade_ellipse(img, head_cx, head_cy, head_r, int(head_r * 1.05), base_val=180)

    # Eye (side view — one eye)
    if not is_skeleton:
        eye_x = head_cx - head_r // 3
        eye_y = head_cy - 1
        er = max(1, head_r // 7)
        draw.ellipse([eye_x - er, eye_y - er, eye_x + er, eye_y + er], fill=30)
    else:
        eye_x = head_cx - head_r // 3
        eye_y = head_cy - 1
        er = max(1, head_r // 5)
        draw.ellipse([eye_x - er, eye_y - er, eye_x + er, eye_y + er], fill=20)

    # Neck
    neck_hw = max(2, int(w * 0.05 * bulk))
    shade_rect(img, head_cx - neck_hw, neck_y - 1, head_cx + neck_hw, torso_top + 2, base_val=140)

    # Torso (side view — narrower, slightly oval)
    torso_hw = body_hw
    torso_cy = (torso_top + torso_bot) // 2
    torso_ry = (torso_bot - torso_top) // 2
    shade_ellipse(img, head_cx, torso_cy, torso_hw, torso_ry, base_val=170)

    # Arm (one visible, slightly bent)
    arm_w = max(2, int(w * 0.06 * bulk))
    arm_x = head_cx - body_hw + arm_w // 2
    arm_top = torso_top + 3
    arm_mid = (torso_top + torso_bot) // 2 + 5
    arm_bot_y = torso_bot + int(h * 0.06)
    shade_rect(img, arm_x - arm_w, arm_top, arm_x + arm_w, arm_bot_y, base_val=140)
    # Hand
    shade_ellipse(img, arm_x, arm_bot_y + 2, arm_w, arm_w, base_val=145)

    # Weapon (side view)
    if weapon == "staff":
        sx = arm_x - arm_w - 2
        for y in range(arm_top - 8, leg_bot):
            if 0 <= sx < w and 0 <= y < h:
                img.putpixel((sx, y), 130)
        shade_ellipse(img, sx, arm_top - 10, 3, 3, base_val=220)
    elif weapon == "sword":
        sx = arm_x - arm_w - 1
        for y in range(arm_top, arm_bot_y + 8):
            if 0 <= sx < w and 0 <= y < h:
                img.putpixel((sx, y), 200)

    # Legs (walking pose — one forward, one back)
    leg_w = max(2, int(w * 0.06 * bulk))
    leg_top_y = torso_bot - 2
    # Front leg (slightly forward)
    front_leg_x = head_cx - 2
    shade_rect(img, front_leg_x - leg_w, leg_top_y,
               front_leg_x + leg_w, leg_bot, base_val=150)
    # Back leg (slightly back)
    back_leg_x = head_cx + 3
    shade_rect(img, back_leg_x - leg_w, leg_top_y,
               back_leg_x + leg_w, leg_bot, base_val=120)

    # Feet
    foot_w = leg_w + 3
    for lx in [front_leg_x, back_leg_x]:
        for x in range(lx - foot_w, lx + 2):
            if 0 <= x < w and leg_bot < h and leg_bot + 1 < h:
                img.putpixel((x, leg_bot), 130)
                img.putpixel((x, leg_bot + 1), 100)

    return img


# ---------------------------------------------------------------------------
# Animal silhouette drawing
# ---------------------------------------------------------------------------

def draw_animal_front(w: int, h: int, *,
                      head_size: float = 0.3,
                      body_round: float = 0.4,
                      has_antlers: bool = False,
                      has_snout: bool = False,
                      has_fleece: bool = False,
                      ear_style: str = "pointed") -> Image.Image:
    """Draw an animal facing the viewer."""
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)
    cx = w // 2

    head_h = int(h * head_size)
    head_r = int(head_h * 0.4)
    head_cy = int(head_h * 0.6)
    body_top = head_h + 4
    body_bot = h - 10
    body_rx = int(w * body_round)
    body_cy = (body_top + body_bot) // 2
    body_ry = (body_bot - body_top) // 2

    # Antlers
    if has_antlers:
        for side in [-1, 1]:
            ax = cx + side * (head_r + 2)
            for i in range(8):
                ay = head_cy - head_r - i * 2
                if 0 <= ax + side * i < w and 0 <= ay < h:
                    img.putpixel((ax + side * i, ay), 160)
                    # Tines
                    if i % 3 == 0 and i > 0:
                        for t in range(4):
                            tx = ax + side * i + side * t
                            ty = ay - t
                            if 0 <= tx < w and 0 <= ty < h:
                                img.putpixel((tx, ty), 140)

    # Ears
    if ear_style == "pointed":
        for side in [-1, 1]:
            ex = cx + side * (head_r - 2)
            ey = head_cy - head_r
            draw.polygon([(ex, ey), (ex + side * 4, ey - 6), (ex + side * 1, ey - 1)], fill=140)
    elif ear_style == "floppy":
        for side in [-1, 1]:
            ex = cx + side * (head_r + 1)
            ey = head_cy - 2
            shade_ellipse(img, ex, ey, 3, 5, base_val=130)

    # Head
    if has_fleece:
        # Dark face on fluffy body
        shade_ellipse(img, cx, head_cy, head_r, int(head_r * 1.0), base_val=100)
    else:
        shade_ellipse(img, cx, head_cy, head_r, int(head_r * 1.0), base_val=170)

    # Eyes
    eye_spread = head_r // 3
    er = max(1, head_r // 7)
    for side in [-1, 1]:
        draw.ellipse([cx + side * eye_spread - er, head_cy - 2 - er,
                      cx + side * eye_spread + er, head_cy - 2 + er], fill=30)

    # Snout
    if has_snout:
        snout_y = head_cy + head_r // 3
        snout_r = head_r // 3
        shade_ellipse(img, cx, snout_y, snout_r + 2, snout_r, base_val=190)
        draw.ellipse([cx - 2, snout_y - 1, cx, snout_y + 1], fill=40)
        draw.ellipse([cx + 1, snout_y - 1, cx + 3, snout_y + 1], fill=40)

    # Body
    if has_fleece:
        # Fluffy cloud-like body
        for angle in range(0, 360, 20):
            ox = int(math.cos(math.radians(angle)) * body_rx * 0.9)
            oy = int(math.sin(math.radians(angle)) * body_ry * 0.9)
            shade_ellipse(img, cx + ox, body_cy + oy, 6, 6, base_val=200)
        shade_ellipse(img, cx, body_cy, body_rx, body_ry, base_val=190)
    else:
        shade_ellipse(img, cx, body_cy, body_rx, body_ry, base_val=170)

    # Legs (four, front view — two visible on each side)
    leg_w = max(2, int(w * 0.06))
    leg_top_y = body_bot - 4
    leg_bot_y = h - 3
    gap = int(w * 0.08)
    for side in [-1, 1]:
        for offset in [gap, gap + leg_w * 2 + 1]:
            lx = cx + side * offset
            shade_rect(img, lx - leg_w, leg_top_y, lx + leg_w, leg_bot_y, base_val=140)

    return img


def draw_animal_side(w: int, h: int, *,
                     head_size: float = 0.25,
                     body_length: float = 0.6,
                     body_height: float = 0.3,
                     has_antlers: bool = False,
                     has_snout: bool = False,
                     has_fleece: bool = False,
                     has_curly_tail: bool = False,
                     ear_style: str = "pointed") -> Image.Image:
    """Draw an animal in side profile (facing left)."""
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)

    # Layout: head on left, body stretches right
    head_h = int(h * head_size)
    head_r = int(head_h * 0.45)
    head_cx = int(w * 0.18)
    head_cy = int(h * 0.3)

    body_cx = int(w * 0.52)
    body_rx = int(w * body_length * 0.5)
    body_ry = int(h * body_height * 0.5)
    body_cy = int(h * 0.45)

    body_bot = body_cy + body_ry
    leg_bot = h - 3

    # Antlers
    if has_antlers:
        for i in range(10):
            ax = head_cx - head_r // 2 + i
            ay = head_cy - head_r - 2 - i
            if 0 <= ax < w and 0 <= ay < h:
                img.putpixel((ax, ay), 160)
            # Tines
            if i % 3 == 0 and i > 2:
                for t in range(5):
                    tx = ax - t
                    ty = ay - t
                    if 0 <= tx < w and 0 <= ty < h:
                        img.putpixel((tx, ty), 140)

    # Ears
    if ear_style == "pointed":
        ex = head_cx + 1
        ey = head_cy - head_r
        draw.polygon([(ex, ey), (ex + 3, ey - 5), (ex + 5, ey)], fill=140)
    elif ear_style == "floppy":
        ex = head_cx + head_r - 1
        ey = head_cy + 2
        shade_ellipse(img, ex, ey, 3, 5, base_val=130)

    # Head
    if has_fleece:
        shade_ellipse(img, head_cx, head_cy, head_r, int(head_r * 0.9), base_val=100)
    else:
        shade_ellipse(img, head_cx, head_cy, head_r, int(head_r * 0.9), base_val=175)

    # Eye
    eye_x = head_cx - head_r // 3
    eye_y = head_cy - 2
    er = max(1, head_r // 6)
    draw.ellipse([eye_x - er, eye_y - er, eye_x + er, eye_y + er], fill=30)

    # Snout
    if has_snout:
        snout_x = head_cx - head_r - 2
        snout_y = head_cy + 2
        shade_ellipse(img, snout_x, snout_y, head_r // 2 + 2, head_r // 3, base_val=185)
        draw.point((snout_x - 2, snout_y), fill=40)
        draw.point((snout_x - 2, snout_y + 1), fill=40)

    # Neck
    neck_x0 = head_cx + head_r // 2
    neck_x1 = body_cx - body_rx + body_rx // 3
    neck_y0 = head_cy + head_r // 3
    neck_y1 = body_cy - body_ry // 2
    shade_trapezoid(img, (neck_x0 + neck_x1) // 2, neck_y0, 4,
                    (neck_x0 + neck_x1) // 2, neck_y1 + 4, 6, base_val=160)

    # Body
    if has_fleece:
        for angle in range(0, 360, 25):
            ox = int(math.cos(math.radians(angle)) * body_rx * 0.85)
            oy = int(math.sin(math.radians(angle)) * body_ry * 0.85)
            shade_ellipse(img, body_cx + ox, body_cy + oy, 5, 5, base_val=200)
        shade_ellipse(img, body_cx, body_cy, body_rx, body_ry, base_val=190)
    else:
        shade_ellipse(img, body_cx, body_cy, body_rx, body_ry, base_val=170)

    # Tail
    if has_curly_tail:
        tail_x = body_cx + body_rx + 2
        tail_y = body_cy - body_ry // 3
        for i in range(6):
            tx = tail_x + int(3 * math.sin(i * 1.2))
            ty = tail_y - i
            if 0 <= tx < w and 0 <= ty < h:
                img.putpixel((tx, ty), 150)
    else:
        # Straight short tail
        tail_x = body_cx + body_rx
        tail_y = body_cy - body_ry // 3
        for i in range(5):
            if tail_x + i < w and 0 <= tail_y - i < h:
                img.putpixel((tail_x + i, tail_y - i), 130)

    # Legs (four visible in profile, pairs slightly offset)
    leg_w = max(2, int(w * 0.045))
    leg_positions = [
        body_cx - body_rx // 2 - 2,  # front-front
        body_cx - body_rx // 2 + 4,  # front-back
        body_cx + body_rx // 2 - 4,  # rear-front
        body_cx + body_rx // 2 + 2,  # rear-back
    ]
    for i, lx in enumerate(leg_positions):
        base_v = 150 if i % 2 == 0 else 120  # Alternate brightness for depth
        shade_rect(img, lx - leg_w, body_bot - 2, lx + leg_w, leg_bot, base_val=base_v)
        # Hoof
        for x in range(lx - leg_w - 1, lx + leg_w + 1):
            if 0 <= x < w and leg_bot < h:
                img.putpixel((x, leg_bot), 100)

    return img


def draw_animal_back(w: int, h: int, *,
                     has_antlers: bool = False,
                     has_fleece: bool = False,
                     has_curly_tail: bool = False,
                     body_round: float = 0.4,
                     ear_style: str = "pointed") -> Image.Image:
    """Draw an animal from behind."""
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)
    cx = w // 2

    head_r = int(w * 0.12)
    head_cy = int(h * 0.15)
    body_cy = int(h * 0.5)
    body_rx = int(w * body_round)
    body_ry = int(h * 0.2)
    body_bot = body_cy + body_ry
    leg_bot = h - 3

    # Back of head
    shade_ellipse(img, cx, head_cy, head_r, head_r, base_val=140)

    # Antlers (from behind)
    if has_antlers:
        for side in [-1, 1]:
            ax = cx + side * (head_r + 1)
            for i in range(7):
                ay = head_cy - head_r - i * 2
                axx = ax + side * i
                if 0 <= axx < w and 0 <= ay < h:
                    img.putpixel((axx, ay), 150)

    # Ears (back view)
    if ear_style == "pointed":
        for side in [-1, 1]:
            ex = cx + side * (head_r - 1)
            ey = head_cy - head_r + 1
            draw.polygon([(ex, ey), (ex + side * 3, ey - 5), (ex + side * 1, ey)], fill=130)

    # Body
    if has_fleece:
        for angle in range(0, 360, 20):
            ox = int(math.cos(math.radians(angle)) * body_rx * 0.9)
            oy = int(math.sin(math.radians(angle)) * body_ry * 0.9)
            shade_ellipse(img, cx + ox, body_cy + oy, 6, 6, base_val=200)
        shade_ellipse(img, cx, body_cy, body_rx, body_ry, base_val=185)
    else:
        shade_ellipse(img, cx, body_cy, body_rx, body_ry, base_val=160)

    # Tail
    if has_curly_tail:
        tail_y = body_cy - body_ry // 2
        for i in range(5):
            tx = cx + int(2 * math.sin(i * 1.5))
            ty = tail_y - i
            if 0 <= tx < w and 0 <= ty < h:
                img.putpixel((tx, ty), 150)
    else:
        tail_y = body_cy - body_ry // 2
        for i in range(4):
            if 0 <= cx < w and 0 <= tail_y - i < h:
                img.putpixel((cx, tail_y - i), 120)

    # Legs
    leg_w = max(2, int(w * 0.06))
    gap = int(w * 0.08)
    for side in [-1, 1]:
        for offset in [gap, gap + leg_w * 2 + 1]:
            lx = cx + side * offset
            shade_rect(img, lx - leg_w, body_bot - 2, lx + leg_w, leg_bot, base_val=140)

    return img


# ---------------------------------------------------------------------------
# Character definitions
# ---------------------------------------------------------------------------

HUMANOID_CANVAS = (64, 128)
ANIMAL_CANVAS = (96, 80)  # Wider for side profiles
AA_HUMANOID = (28, 30)    # aalib grid for humanoids
AA_ANIMAL = (36, 20)      # aalib grid for animals

CHARACTERS = {
    "mage": {
        "type": "humanoid",
        "front_kw": {"hat": "wizard", "weapon": "staff",
                     "shoulder_width": 0.4, "head_ratio": 0.2},
        "back_kw":  {"hat": "wizard", "weapon": "staff",
                     "shoulder_width": 0.4, "head_ratio": 0.2},
        "side_kw":  {"hat": "wizard", "weapon": "staff",
                     "body_width": 0.3, "head_ratio": 0.2},
    },
    "warrior": {
        "type": "humanoid",
        "front_kw": {"hat": "helmet", "weapon": "sword",
                     "shoulder_width": 0.55, "bulk": 1.15, "head_ratio": 0.18},
        "back_kw":  {"hat": "helmet", "weapon": "sword",
                     "shoulder_width": 0.55, "bulk": 1.15, "head_ratio": 0.18},
        "side_kw":  {"hat": "helmet", "weapon": "sword",
                     "body_width": 0.4, "bulk": 1.15, "head_ratio": 0.18},
    },
    "zombie_walker": {
        "type": "humanoid",
        "front_kw": {"shoulder_width": 0.42, "waist_width": 0.3,
                     "head_ratio": 0.18},
        "back_kw":  {"shoulder_width": 0.42, "waist_width": 0.3,
                     "head_ratio": 0.18},
        "side_kw":  {"body_width": 0.3, "head_ratio": 0.18},
    },
    "zombie_runner": {
        "type": "humanoid",
        "front_kw": {"shoulder_width": 0.38, "waist_width": 0.28,
                     "head_ratio": 0.17, "bulk": 0.9},
        "back_kw":  {"shoulder_width": 0.38, "waist_width": 0.28,
                     "head_ratio": 0.17, "bulk": 0.9},
        "side_kw":  {"body_width": 0.28, "head_ratio": 0.17, "bulk": 0.9},
    },
    "zombie_brute": {
        "type": "humanoid",
        "front_kw": {"shoulder_width": 0.6, "waist_width": 0.5,
                     "head_ratio": 0.15, "bulk": 1.3},
        "back_kw":  {"shoulder_width": 0.6, "waist_width": 0.5,
                     "head_ratio": 0.15, "bulk": 1.3},
        "side_kw":  {"body_width": 0.45, "head_ratio": 0.15, "bulk": 1.3},
    },
    "alice": {
        "type": "humanoid",
        "front_kw": {"shoulder_width": 0.38, "waist_width": 0.32,
                     "head_ratio": 0.22},
        "back_kw":  {"shoulder_width": 0.38, "waist_width": 0.32,
                     "head_ratio": 0.22},
        "side_kw":  {"body_width": 0.3, "head_ratio": 0.22},
    },
    "skeleton": {
        "type": "humanoid",
        "front_kw": {"shoulder_width": 0.4, "waist_width": 0.28,
                     "head_ratio": 0.2, "is_skeleton": True, "bulk": 0.85},
        "back_kw":  {"shoulder_width": 0.4, "waist_width": 0.28,
                     "head_ratio": 0.2, "bulk": 0.85},
        "side_kw":  {"body_width": 0.28, "head_ratio": 0.2,
                     "is_skeleton": True, "bulk": 0.85},
    },
    "deer": {
        "type": "animal",
        "front_kw": {"has_antlers": True, "head_size": 0.25,
                     "body_round": 0.35, "ear_style": "pointed"},
        "side_kw":  {"has_antlers": True, "head_size": 0.25,
                     "body_length": 0.55, "body_height": 0.3,
                     "ear_style": "pointed"},
        "back_kw":  {"has_antlers": True, "body_round": 0.35,
                     "ear_style": "pointed"},
    },
    "pig": {
        "type": "animal",
        "front_kw": {"has_snout": True, "head_size": 0.3,
                     "body_round": 0.42, "ear_style": "floppy"},
        "side_kw":  {"has_snout": True, "head_size": 0.28,
                     "body_length": 0.5, "body_height": 0.32,
                     "has_curly_tail": True, "ear_style": "floppy"},
        "back_kw":  {"has_curly_tail": True, "body_round": 0.42,
                     "ear_style": "floppy"},
    },
    "sheep": {
        "type": "animal",
        "front_kw": {"has_fleece": True, "head_size": 0.28,
                     "body_round": 0.45, "ear_style": "floppy"},
        "side_kw":  {"has_fleece": True, "head_size": 0.25,
                     "body_length": 0.5, "body_height": 0.35,
                     "ear_style": "floppy"},
        "back_kw":  {"has_fleece": True, "body_round": 0.45,
                     "ear_style": "floppy"},
    },
}


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

def generate_character(name: str):
    """Generate all four angle sprites for a character."""
    if name not in CHARACTERS:
        print(f"  Unknown character: {name}")
        return

    char = CHARACTERS[name]
    palette = PALETTES.get(name, PALETTES["alice"])
    out_dir = OUT_BASE / name
    out_dir.mkdir(parents=True, exist_ok=True)

    is_animal = char["type"] == "animal"
    canvas = ANIMAL_CANVAS if is_animal else HUMANOID_CANVAS
    aa_size = AA_ANIMAL if is_animal else AA_HUMANOID

    angles = {}
    if is_animal:
        angles["front"] = draw_animal_front(canvas[0], canvas[1], **char["front_kw"])
        angles["back"] = draw_animal_back(canvas[0], canvas[1], **char["back_kw"])
        angles["left"] = draw_animal_side(canvas[0], canvas[1], **char["side_kw"])
    else:
        angles["front"] = draw_humanoid_front(canvas[0], canvas[1], **char["front_kw"])
        angles["back"] = draw_humanoid_back(canvas[0], canvas[1], **char["back_kw"])
        angles["left"] = draw_humanoid_side(canvas[0], canvas[1], **char["side_kw"])

    count = 0
    for angle_name, silhouette in angles.items():
        aa_lines = image_to_aalib(silhouette, aa_size[0], aa_size[1])
        aa_lines = [line.rstrip() for line in aa_lines]
        while aa_lines and not aa_lines[0].strip():
            aa_lines.pop(0)
        while aa_lines and not aa_lines[-1].strip():
            aa_lines.pop()

        if aa_lines:
            sprite = render_aa_text(aa_lines, palette, scale=3)
            sprite.save(str(out_dir / f"{angle_name}.png"))
            count += 1

    # Right is a horizontal flip of left
    left_path = out_dir / "left.png"
    if left_path.exists():
        left_img = Image.open(str(left_path))
        right_img = left_img.transpose(Image.FLIP_LEFT_RIGHT)
        right_img.save(str(out_dir / "right.png"))
        count += 1

    print(f"  {name}: {count} sprites -> {out_dir.relative_to(OUT_BASE.parent.parent)}")


def main():
    parser = argparse.ArgumentParser(description="Generate aalib character sprites for Hamberg")
    parser.add_argument("--characters", nargs="*",
                        help="Specific characters to generate (default: all)")
    args = parser.parse_args()

    chars = args.characters or list(CHARACTERS.keys())
    OUT_BASE.mkdir(parents=True, exist_ok=True)

    print("Generating aalib character sprites:")
    for name in chars:
        generate_character(name)
    print(f"\nDone. Output: {OUT_BASE.relative_to(OUT_BASE.parent.parent)}")


if __name__ == "__main__":
    main()
