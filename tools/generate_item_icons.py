#!/usr/bin/env python3
"""
Generate item icons for inventory/hotbar using pycairo.
Same blue/gold Hollow Knight palette as environment textures.
Outputs 64x64 PNGs to images/icons/ for the game's inventory system.

Usage: python3 tools/generate_item_icons.py
"""

import cairo
import math
import random
from pathlib import Path
from PIL import Image

random.seed(42)

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "images" / "icons"

# ── Color palette (matching environment textures) ────────────────────────────
LEAF_BRIGHT = (0.55, 0.65, 0.95)
LEAF_LIGHT  = (0.35, 0.48, 0.85)
LEAF_MED    = (0.20, 0.35, 0.72)
LEAF_DARK   = (0.10, 0.20, 0.55)
LEAF_SHADOW = (0.05, 0.10, 0.38)

BARK_LIGHT  = (0.25, 0.30, 0.52)
BARK_MED    = (0.15, 0.20, 0.42)
BARK_DARK   = (0.08, 0.12, 0.30)
BARK_SHADOW = (0.04, 0.06, 0.20)

GOLD_BRIGHT = (1.0, 0.92, 0.5)
GOLD_PRIMARY= (1.0, 0.792, 0.0)
GOLD_DARK   = (0.7, 0.55, 0.0)
GOLD_METAL  = (1.0, 0.95, 0.7)

BLUE_PRIMARY= (0.0, 0.204, 1.0)
BLUE_DARK   = (0.0, 0.1, 0.5)
BLUE_LIGHT  = (0.45, 0.55, 1.0)

WHITE       = (0.9, 0.92, 1.0)
GRAY_LIGHT  = (0.5, 0.52, 0.65)
GRAY_MED    = (0.3, 0.32, 0.45)
GRAY_DARK   = (0.15, 0.17, 0.28)

STONE_LIGHT = (0.4, 0.42, 0.58)
STONE_MED   = (0.28, 0.30, 0.45)
STONE_DARK  = (0.18, 0.20, 0.32)

IRON_LIGHT  = (0.55, 0.58, 0.72)
IRON_MED    = (0.4, 0.42, 0.55)
IRON_DARK   = (0.25, 0.27, 0.4)

RED_BRIGHT  = (1.0, 0.3, 0.2)
RED_MED     = (0.8, 0.2, 0.15)
RED_DARK    = (0.5, 0.1, 0.1)

PINK_BRIGHT = (1.0, 0.45, 0.65)
PINK_DARK   = (0.6, 0.15, 0.35)

PURPLE_BRIGHT = (0.6, 0.3, 0.9)
PURPLE_DARK   = (0.3, 0.1, 0.5)

CYAN_BRIGHT = (0.3, 0.9, 0.9)
CYAN_DARK   = (0.1, 0.5, 0.5)

ORANGE_BRIGHT = (1.0, 0.6, 0.2)
ORANGE_DARK   = (0.7, 0.35, 0.05)

BONE_LIGHT  = (0.75, 0.72, 0.65)
BONE_MED    = (0.6, 0.55, 0.48)
BONE_DARK   = (0.4, 0.35, 0.3)

LEATHER_LIGHT = (0.45, 0.35, 0.55)
LEATHER_DARK  = (0.25, 0.18, 0.35)

POTION_GLASS = (0.5, 0.55, 0.75)

SZ = 64  # Icon size


# ── Helpers ──────────────────────────────────────────────────────────────────

def make_surface(w=SZ, h=SZ):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surface)
    ctx.set_antialias(cairo.ANTIALIAS_BEST)
    ctx.set_operator(cairo.OPERATOR_OVER)
    ctx.set_source_rgba(0, 0, 0, 0)
    ctx.set_operator(cairo.OPERATOR_SOURCE)
    ctx.paint()
    ctx.set_operator(cairo.OPERATOR_OVER)
    return surface, ctx


def save_icon(surface, name):
    w, h = surface.get_width(), surface.get_height()
    buf = surface.get_data()
    img = Image.frombuffer("RGBA", (w, h), bytes(buf), "raw", "BGRA", 0, 1)
    path = OUTPUT_DIR / f"{name}.png"
    img.save(str(path), "PNG")
    print(f"  {name}.png")


def sc(ctx, rgb, alpha=1.0):
    """Set color."""
    ctx.set_source_rgba(*rgb, alpha)


def circle(ctx, cx, cy, r, rgb, alpha=1.0):
    ctx.arc(cx, cy, r, 0, 2 * math.pi)
    sc(ctx, rgb, alpha)
    ctx.fill()


def rcircle(ctx, cx, cy, r, inner, outer, ia=1.0, oa=1.0):
    """Radial gradient circle."""
    pat = cairo.RadialGradient(cx - r * 0.25, cy - r * 0.25, r * 0.05, cx, cy, r)
    pat.add_color_stop_rgba(0, *inner, ia)
    pat.add_color_stop_rgba(1, *outer, oa)
    ctx.arc(cx, cy, r, 0, 2 * math.pi)
    ctx.set_source(pat)
    ctx.fill()


def rounded_rect(ctx, x, y, w, h, r=4):
    ctx.new_sub_path()
    ctx.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    ctx.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    ctx.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    ctx.close_path()


def blade(ctx, cx, cy, length, width, tip_color, base_color, angle=0):
    """Draw a blade shape (sword/knife) at an angle."""
    ctx.save()
    ctx.translate(cx, cy)
    ctx.rotate(angle)
    pat = cairo.LinearGradient(0, -length / 2, 0, length / 2)
    pat.add_color_stop_rgb(0, *tip_color)
    pat.add_color_stop_rgb(1, *base_color)
    # Blade shape
    ctx.move_to(0, -length / 2)
    ctx.line_to(width / 2, -length / 4)
    ctx.line_to(width / 2, length / 2 - 4)
    ctx.line_to(0, length / 2)
    ctx.line_to(-width / 2, length / 2 - 4)
    ctx.line_to(-width / 2, -length / 4)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()
    ctx.restore()


def handle(ctx, cx, cy, length, width, color1, color2, angle=0):
    """Draw a weapon handle."""
    ctx.save()
    ctx.translate(cx, cy)
    ctx.rotate(angle)
    pat = cairo.LinearGradient(-width / 2, 0, width / 2, 0)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    rounded_rect(ctx, -width / 2, -length / 2, width, length, 2)
    ctx.set_source(pat)
    ctx.fill()
    ctx.restore()


# ── RESOURCE ICONS ───────────────────────────────────────────────────────────

def icon_wood():
    s, c = make_surface()
    # Log cross-section
    rcircle(c, 32, 28, 18, BARK_LIGHT, BARK_DARK)
    rcircle(c, 32, 28, 13, BARK_MED, BARK_SHADOW)
    # Rings
    for r in [4, 8, 11]:
        c.arc(32, 28, r, 0, 2 * math.pi)
        c.set_line_width(0.8)
        sc(c, BARK_SHADOW, 0.4)
        c.stroke()
    # Center dot
    circle(c, 32, 28, 2, BARK_LIGHT)
    # Second small log behind
    rcircle(c, 22, 42, 10, BARK_LIGHT, BARK_DARK)
    rcircle(c, 22, 42, 7, BARK_MED, BARK_SHADOW)
    save_icon(s, "wood")


def icon_stone():
    s, c = make_surface()
    # Chunky rock shape
    c.move_to(15, 45)
    c.line_to(10, 28)
    c.line_to(20, 15)
    c.line_to(38, 12)
    c.line_to(52, 20)
    c.line_to(54, 38)
    c.line_to(45, 48)
    c.close_path()
    pat = cairo.LinearGradient(10, 12, 54, 48)
    pat.add_color_stop_rgb(0, *STONE_LIGHT)
    pat.add_color_stop_rgb(1, *STONE_DARK)
    c.set_source(pat)
    c.fill()
    # Crack lines
    c.set_line_width(1)
    sc(c, STONE_DARK, 0.5)
    c.move_to(30, 20)
    c.line_to(35, 35)
    c.line_to(28, 42)
    c.stroke()
    # Highlight
    circle(c, 28, 22, 3, STONE_LIGHT, 0.4)
    save_icon(s, "stone")


def icon_earth():
    s, c = make_surface()
    # Dirt mound
    c.move_to(8, 50)
    c.curve_to(8, 25, 32, 10, 56, 25)
    c.line_to(56, 50)
    c.close_path()
    pat = cairo.LinearGradient(32, 10, 32, 50)
    pat.add_color_stop_rgb(0, *BARK_MED)
    pat.add_color_stop_rgb(1, *BARK_SHADOW)
    c.set_source(pat)
    c.fill()
    # Dirt specks
    for _ in range(8):
        x = random.uniform(14, 50)
        y = random.uniform(25, 46)
        circle(c, x, y, random.uniform(1, 2.5), BARK_LIGHT, 0.4)
    save_icon(s, "earth")


def icon_resin():
    s, c = make_surface()
    # Amber drop shape
    c.move_to(32, 10)
    c.curve_to(42, 20, 48, 35, 40, 48)
    c.curve_to(36, 54, 28, 54, 24, 48)
    c.curve_to(16, 35, 22, 20, 32, 10)
    c.close_path()
    pat = cairo.RadialGradient(28, 25, 3, 32, 35, 22)
    pat.add_color_stop_rgba(0, *GOLD_BRIGHT, 0.9)
    pat.add_color_stop_rgba(1, *GOLD_DARK, 0.85)
    c.set_source(pat)
    c.fill()
    # Shine
    circle(c, 28, 22, 4, WHITE, 0.4)
    save_icon(s, "resin")


def icon_iron():
    s, c = make_surface()
    # Iron ingot
    c.move_to(12, 42)
    c.line_to(20, 18)
    c.line_to(52, 18)
    c.line_to(52, 42)
    c.close_path()
    pat = cairo.LinearGradient(12, 18, 52, 42)
    pat.add_color_stop_rgb(0, *IRON_LIGHT)
    pat.add_color_stop_rgb(1, *IRON_DARK)
    c.set_source(pat)
    c.fill()
    # Top face
    c.move_to(20, 18)
    c.line_to(28, 12)
    c.line_to(58, 12)
    c.line_to(52, 18)
    c.close_path()
    sc(c, IRON_LIGHT)
    c.fill()
    # Shine
    c.set_line_width(1.5)
    sc(c, WHITE, 0.3)
    c.move_to(30, 16)
    c.line_to(45, 16)
    c.stroke()
    save_icon(s, "iron")


def icon_copper():
    s, c = make_surface()
    COPPER_L = (0.7, 0.45, 0.3)
    COPPER_D = (0.45, 0.25, 0.15)
    # Copper ore chunk
    c.move_to(14, 44)
    c.line_to(10, 25)
    c.line_to(25, 14)
    c.line_to(42, 12)
    c.line_to(52, 22)
    c.line_to(50, 42)
    c.line_to(38, 48)
    c.close_path()
    pat = cairo.LinearGradient(10, 12, 52, 48)
    pat.add_color_stop_rgb(0, *COPPER_L)
    pat.add_color_stop_rgb(1, *COPPER_D)
    c.set_source(pat)
    c.fill()
    # Green patina spots
    for _ in range(4):
        x = random.uniform(18, 45)
        y = random.uniform(18, 42)
        circle(c, x, y, random.uniform(2, 4), LEAF_MED, 0.3)
    save_icon(s, "copper")


def icon_plant_fiber():
    s, c = make_surface()
    # Bundle of fibers
    for i in range(5):
        x = 24 + i * 4
        c.set_line_width(3)
        c.move_to(x, 52)
        c.curve_to(x - 3, 35, x + 2, 20, x - 1 + i * 2, 10)
        sc(c, LEAF_MED if i % 2 == 0 else LEAF_LIGHT)
        c.stroke()
    save_icon(s, "plant_fiber")


def icon_rope():
    s, c = make_surface()
    # Coiled rope
    c.set_line_width(4)
    for i in range(3):
        y = 18 + i * 12
        c.arc(32, y, 12, 0.3, math.pi + 0.3)
        sc(c, BARK_LIGHT if i % 2 == 0 else BARK_MED)
        c.stroke()
    save_icon(s, "rope")


def icon_arrows():
    s, c = make_surface()
    # Three arrows
    for dx in [-6, 0, 6]:
        x = 32 + dx
        # Shaft
        c.set_line_width(2)
        sc(c, BARK_MED)
        c.move_to(x, 52)
        c.line_to(x, 14)
        c.stroke()
        # Arrowhead
        c.move_to(x, 10)
        c.line_to(x - 4, 18)
        c.line_to(x + 4, 18)
        c.close_path()
        sc(c, STONE_LIGHT)
        c.fill()
        # Fletching
        c.move_to(x, 50)
        c.line_to(x - 3, 46)
        c.move_to(x, 48)
        c.line_to(x + 3, 44)
        c.set_line_width(1.5)
        sc(c, LEAF_LIGHT, 0.7)
        c.stroke()
    save_icon(s, "arrows")


def icon_charcoal():
    s, c = make_surface()
    # Dark lumps
    for cx_, cy_, r in [(24, 32, 12), (38, 28, 10), (30, 42, 9)]:
        rcircle(c, cx_, cy_, r, GRAY_DARK, (0.05, 0.05, 0.1))
        # Ember glow
        circle(c, cx_ + random.uniform(-3, 3), cy_ + random.uniform(-3, 3),
               r * 0.3, RED_MED, 0.3)
    save_icon(s, "charcoal")


def icon_bone():
    s, c = make_surface()
    # Bone shape
    c.set_line_width(6)
    sc(c, BONE_LIGHT)
    c.move_to(16, 48)
    c.line_to(48, 16)
    c.stroke()
    # Knobs at ends
    circle(c, 14, 50, 5, BONE_LIGHT)
    circle(c, 18, 46, 4, BONE_LIGHT)
    circle(c, 46, 18, 5, BONE_LIGHT)
    circle(c, 50, 14, 4, BONE_LIGHT)
    # Shadow
    circle(c, 15, 50, 5, BONE_DARK, 0.3)
    save_icon(s, "bone")


def icon_rotten_flesh():
    s, c = make_surface()
    # Gross meat chunk
    c.move_to(14, 40)
    c.curve_to(10, 25, 25, 15, 40, 18)
    c.curve_to(52, 20, 54, 35, 48, 44)
    c.curve_to(40, 50, 20, 48, 14, 40)
    c.close_path()
    pat = cairo.LinearGradient(14, 15, 48, 48)
    pat.add_color_stop_rgb(0, 0.25, 0.3, 0.2)
    pat.add_color_stop_rgb(1, 0.15, 0.18, 0.12)
    c.set_source(pat)
    c.fill()
    # Gross spots
    for _ in range(4):
        circle(c, random.uniform(20, 44), random.uniform(22, 42),
               random.uniform(2, 4), (0.35, 0.4, 0.15), 0.5)
    save_icon(s, "rotten_flesh")


def icon_glowing_spore():
    s, c = make_surface()
    # Glowing orb
    rcircle(c, 32, 32, 16, CYAN_BRIGHT, CYAN_DARK)
    # Glow aura
    rcircle(c, 32, 32, 22, CYAN_BRIGHT, CYAN_DARK, 0.2, 0.0)
    circle(c, 28, 26, 4, WHITE, 0.5)
    save_icon(s, "glowing_spore")


def icon_fungal_essence():
    s, c = make_surface()
    # Small vial with purple liquid
    _draw_vial(c, 32, 32, PURPLE_BRIGHT, PURPLE_DARK)
    save_icon(s, "fungal_essence")


def _draw_vial(c, cx, cy, color_top, color_bot):
    """Small potion vial shape."""
    # Neck
    rounded_rect(c, cx - 4, cy - 18, 8, 10, 2)
    sc(c, POTION_GLASS)
    c.fill()
    # Body
    c.move_to(cx - 4, cy - 10)
    c.line_to(cx - 12, cy)
    c.line_to(cx - 12, cy + 16)
    c.curve_to(cx - 12, cy + 22, cx + 12, cy + 22, cx + 12, cy + 16)
    c.line_to(cx + 12, cy)
    c.line_to(cx + 4, cy - 10)
    c.close_path()
    pat = cairo.LinearGradient(cx, cy - 10, cx, cy + 20)
    pat.add_color_stop_rgb(0, *color_top)
    pat.add_color_stop_rgb(1, *color_bot)
    c.set_source(pat)
    c.fill()
    # Glass shine
    c.set_line_width(1.5)
    sc(c, WHITE, 0.3)
    c.move_to(cx - 8, cy + 2)
    c.line_to(cx - 8, cy + 14)
    c.stroke()
    # Cork
    rounded_rect(c, cx - 5, cy - 20, 10, 5, 2)
    sc(c, BARK_LIGHT)
    c.fill()


def _draw_leather(c, color):
    """Generic leather piece icon."""
    s, c2 = make_surface()
    c2.move_to(12, 48)
    c2.curve_to(8, 30, 18, 12, 35, 10)
    c2.curve_to(50, 10, 55, 25, 52, 42)
    c2.curve_to(48, 52, 15, 54, 12, 48)
    c2.close_path()
    pat = cairo.LinearGradient(12, 10, 52, 50)
    pat.add_color_stop_rgb(0, *color)
    pat.add_color_stop_rgb(1, *(c * 0.6 for c in color))
    c2.set_source(pat)
    c2.fill()
    # Stitch marks
    c2.set_line_width(1)
    sc(c2, WHITE, 0.3)
    for i in range(4):
        y = 18 + i * 9
        c2.move_to(22, y)
        c2.line_to(26, y + 3)
        c2.stroke()
    return s, c2


def icon_pig_leather():
    s, c = make_surface()
    c.move_to(12, 48)
    c.curve_to(8, 30, 18, 12, 35, 10)
    c.curve_to(50, 10, 55, 25, 52, 42)
    c.curve_to(48, 52, 15, 54, 12, 48)
    c.close_path()
    pat = cairo.LinearGradient(12, 10, 52, 50)
    pat.add_color_stop_rgb(0, *PINK_BRIGHT)
    pat.add_color_stop_rgb(1, *PINK_DARK)
    c.set_source(pat)
    c.fill()
    save_icon(s, "pig_leather")


def icon_deer_leather():
    s, c = make_surface()
    c.move_to(12, 48)
    c.curve_to(8, 30, 18, 12, 35, 10)
    c.curve_to(50, 10, 55, 25, 52, 42)
    c.curve_to(48, 52, 15, 54, 12, 48)
    c.close_path()
    pat = cairo.LinearGradient(12, 10, 52, 50)
    pat.add_color_stop_rgb(0, *LEATHER_LIGHT)
    pat.add_color_stop_rgb(1, *LEATHER_DARK)
    c.set_source(pat)
    c.fill()
    save_icon(s, "deer_leather")


# ── RAW MEAT ─────────────────────────────────────────────────────────────────

def _draw_meat(c, color1, color2, name):
    s, ctx = make_surface()
    # Meat cut shape
    ctx.move_to(14, 38)
    ctx.curve_to(10, 22, 22, 12, 38, 14)
    ctx.curve_to(52, 16, 54, 32, 48, 42)
    ctx.curve_to(42, 50, 20, 48, 14, 38)
    ctx.close_path()
    pat = cairo.LinearGradient(14, 12, 48, 48)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    ctx.set_source(pat)
    ctx.fill()
    # Fat marbling
    ctx.set_line_width(1)
    sc(ctx, WHITE, 0.25)
    for _ in range(3):
        x = random.uniform(20, 42)
        y = random.uniform(20, 40)
        ctx.move_to(x, y)
        ctx.curve_to(x + 5, y - 3, x + 8, y + 2, x + 10, y)
        ctx.stroke()
    save_icon(s, name)


def icon_raw_venison(): _draw_meat(None, RED_MED, RED_DARK, "raw_venison")
def icon_raw_pork(): _draw_meat(None, PINK_BRIGHT, PINK_DARK, "raw_pork")
def icon_raw_mutton(): _draw_meat(None, RED_BRIGHT, RED_DARK, "raw_mutton")


# ── FOOD ICONS ───────────────────────────────────────────────────────────────

def _draw_cooked_meat(name, color1, color2):
    s, c = make_surface()
    # Drumstick shape
    # Bone handle
    c.set_line_width(5)
    sc(c, BONE_LIGHT)
    c.move_to(42, 48)
    c.line_to(50, 40)
    c.stroke()
    circle(c, 50, 40, 3, BONE_LIGHT)
    # Meat body
    c.move_to(18, 40)
    c.curve_to(10, 28, 18, 14, 32, 16)
    c.curve_to(44, 18, 48, 30, 44, 40)
    c.curve_to(40, 48, 22, 48, 18, 40)
    c.close_path()
    pat = cairo.LinearGradient(18, 14, 44, 48)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    c.set_source(pat)
    c.fill()
    # Grill marks
    c.set_line_width(1.5)
    sc(c, BARK_SHADOW, 0.4)
    for i in range(3):
        y = 22 + i * 8
        c.move_to(20, y)
        c.line_to(40, y)
        c.stroke()
    save_icon(s, name)


def icon_cooked_venison(): _draw_cooked_meat("cooked_venison", (0.55, 0.25, 0.15), (0.35, 0.15, 0.08))
def icon_cooked_pork(): _draw_cooked_meat("cooked_pork", (0.65, 0.35, 0.25), (0.4, 0.2, 0.12))
def icon_cooked_mutton(): _draw_cooked_meat("cooked_mutton", (0.5, 0.22, 0.12), (0.3, 0.12, 0.06))


def icon_pinkberry():
    s, c = make_surface()
    # Cluster of pink berries
    positions = [(26, 28), (38, 26), (32, 38), (22, 38), (40, 36)]
    for bx, by in positions:
        rcircle(c, bx, by, 8, PINK_BRIGHT, PINK_DARK)
        circle(c, bx - 2, by - 2, 2.5, WHITE, 0.5)
    # Tiny leaf
    c.move_to(32, 16)
    c.curve_to(38, 12, 42, 16, 38, 22)
    c.curve_to(34, 18, 32, 18, 32, 16)
    c.close_path()
    sc(c, LEAF_MED)
    c.fill()
    save_icon(s, "pinkberry")


def icon_rootbeer():
    s, c = make_surface()
    ROOT_L = (0.35, 0.28, 0.55)
    ROOT_D = (0.18, 0.14, 0.35)
    # Thick root
    c.move_to(26, 12)
    c.curve_to(18, 18, 16, 35, 22, 50)
    c.line_to(42, 50)
    c.curve_to(48, 35, 46, 18, 38, 12)
    c.close_path()
    pat = cairo.LinearGradient(26, 12, 38, 50)
    pat.add_color_stop_rgb(0, *ROOT_L)
    pat.add_color_stop_rgb(1, *ROOT_D)
    c.set_source(pat)
    c.fill()
    # Root lines
    c.set_line_width(0.8)
    for i in range(4):
        y = 18 + i * 8
        c.move_to(24, y)
        c.line_to(40, y)
        sc(c, ROOT_D, 0.4)
        c.stroke()
    # Small rootlets
    c.set_line_width(1.5)
    for dx in [-4, 2, 6]:
        c.move_to(32 + dx, 48)
        c.curve_to(32 + dx + 2, 53, 32 + dx - 1, 56, 32 + dx, 58)
        sc(c, ROOT_D, 0.6)
        c.stroke()
    save_icon(s, "rootbeer")


def icon_rootbeer_seed():
    s, c = make_surface()
    # Small seed
    c.move_to(32, 18)
    c.curve_to(40, 22, 42, 38, 36, 48)
    c.curve_to(32, 52, 28, 52, 28, 48)
    c.curve_to(22, 38, 24, 22, 32, 18)
    c.close_path()
    pat = cairo.RadialGradient(30, 30, 2, 32, 36, 16)
    pat.add_color_stop_rgb(0, *BARK_LIGHT)
    pat.add_color_stop_rgb(1, *BARK_DARK)
    c.set_source(pat)
    c.fill()
    save_icon(s, "rootbeer_seed")


def icon_cooked_rootbeer():
    s, c = make_surface()
    # Mug shape
    rounded_rect(c, 16, 18, 28, 34, 4)
    pat = cairo.LinearGradient(16, 18, 44, 52)
    pat.add_color_stop_rgb(0, *BARK_LIGHT)
    pat.add_color_stop_rgb(1, *BARK_DARK)
    c.set_source(pat)
    c.fill()
    # Liquid inside (golden)
    rounded_rect(c, 18, 22, 24, 26, 3)
    pat = cairo.LinearGradient(18, 22, 42, 48)
    pat.add_color_stop_rgb(0, *GOLD_BRIGHT)
    pat.add_color_stop_rgb(1, *GOLD_DARK)
    c.set_source(pat)
    c.fill()
    # Foam
    for x in range(20, 42, 5):
        circle(c, x, 23, 3, WHITE, 0.7)
    # Handle
    c.set_line_width(4)
    sc(c, BARK_MED)
    c.arc(48, 35, 8, -math.pi / 3, math.pi / 3)
    c.stroke()
    save_icon(s, "cooked_rootbeer")


def _draw_food_generic(name, color1, color2, shape="round"):
    """Generic food icon."""
    s, c = make_surface()
    if shape == "round":
        rcircle(c, 32, 32, 18, color1, color2)
        circle(c, 26, 26, 4, WHITE, 0.3)
    elif shape == "long":
        c.move_to(14, 35)
        c.curve_to(14, 20, 50, 15, 50, 30)
        c.curve_to(50, 45, 14, 48, 14, 35)
        c.close_path()
        pat = cairo.LinearGradient(14, 15, 50, 48)
        pat.add_color_stop_rgb(0, *color1)
        pat.add_color_stop_rgb(1, *color2)
        c.set_source(pat)
        c.fill()
    save_icon(s, name)


def icon_dark_mushroom():
    s, c = make_surface()
    # Stem
    rounded_rect(c, 28, 32, 8, 22, 2)
    sc(c, BARK_DARK)
    c.fill()
    # Cap
    c.arc(32, 30, 16, math.pi, 2 * math.pi)
    c.close_path()
    pat = cairo.LinearGradient(16, 14, 48, 30)
    pat.add_color_stop_rgb(0, *PURPLE_BRIGHT)
    pat.add_color_stop_rgb(1, *PURPLE_DARK)
    c.set_source(pat)
    c.fill()
    # Spots
    for _ in range(3):
        circle(c, random.uniform(22, 42), random.uniform(18, 28),
               random.uniform(2, 3), GOLD_BRIGHT, 0.4)
    save_icon(s, "dark_mushroom")


def icon_truffle(): _draw_food_generic("truffle", BARK_MED, BARK_SHADOW, "round")
def icon_swamp_root(): _draw_food_generic("swamp_root", LEAF_DARK, BARK_SHADOW, "long")
def icon_frost_berry(): _draw_food_generic("frost_berry", CYAN_BRIGHT, CYAN_DARK, "round")
def icon_prickly_fruit(): _draw_food_generic("prickly_fruit", GOLD_BRIGHT, GOLD_DARK, "round")
def icon_mana_fruit(): _draw_food_generic("mana_fruit", PURPLE_BRIGHT, BLUE_LIGHT, "round")
def icon_ember_pepper(): _draw_food_generic("ember_pepper", RED_BRIGHT, RED_DARK, "long")

def icon_cooked_truffle(): _draw_food_generic("cooked_truffle", BARK_LIGHT, BARK_MED, "round")
def icon_cooked_frost_berry(): _draw_food_generic("cooked_frost_berry", CYAN_BRIGHT, BLUE_LIGHT, "round")
def icon_cooked_prickly_fruit(): _draw_food_generic("cooked_prickly_fruit", GOLD_PRIMARY, GOLD_DARK, "round")
def icon_cooked_mana_fruit(): _draw_food_generic("cooked_mana_fruit", PURPLE_BRIGHT, PURPLE_DARK, "round")
def icon_cooked_ember_pepper(): _draw_food_generic("cooked_ember_pepper", RED_MED, RED_DARK, "long")

# Seeds (tiny teardrop)
def _draw_seed(name, color):
    s, c = make_surface()
    c.move_to(32, 18)
    c.curve_to(40, 24, 40, 42, 32, 48)
    c.curve_to(24, 42, 24, 24, 32, 18)
    c.close_path()
    pat = cairo.RadialGradient(30, 30, 2, 32, 36, 14)
    pat.add_color_stop_rgb(0, *color)
    pat.add_color_stop_rgb(1, *(x * 0.5 for x in color))
    c.set_source(pat)
    c.fill()
    circle(c, 30, 28, 2, WHITE, 0.3)
    save_icon(s, name)

def icon_nightshade_berry(): _draw_food_generic("nightshade_berry", PURPLE_DARK, (0.15, 0.05, 0.25), "round")
def icon_fungal_seed(): _draw_seed("fungal_seed", PURPLE_BRIGHT)
def icon_lotus_seed(): _draw_seed("lotus_seed", LEAF_LIGHT)
def icon_ice_crystal_seed(): _draw_seed("ice_crystal_seed", CYAN_BRIGHT)
def icon_sun_seed(): _draw_seed("sun_seed", GOLD_BRIGHT)
def icon_ash_seed(): _draw_seed("ash_seed", RED_MED)
def icon_crystal_seed(): _draw_seed("crystal_seed", PURPLE_BRIGHT)
def icon_marsh_herb(): _draw_food_generic("marsh_herb", LEAF_LIGHT, LEAF_DARK, "long")
def icon_alpine_herb(): _draw_food_generic("alpine_herb", CYAN_BRIGHT, LEAF_DARK, "long")
def icon_desert_sage(): _draw_food_generic("desert_sage", GOLD_BRIGHT, LEAF_DARK, "long")
def icon_arcane_herb(): _draw_food_generic("arcane_herb", PURPLE_BRIGHT, LEAF_DARK, "long")
def icon_brimstone_root(): _draw_food_generic("brimstone_root", RED_BRIGHT, ORANGE_DARK, "long")


# ── POTION ICONS ─────────────────────────────────────────────────────────────

def _draw_potion(name, color1, color2):
    s, c = make_surface()
    _draw_vial(c, 32, 32, color1, color2)
    save_icon(s, name)

def icon_healing_potion(): _draw_potion("healing_potion", RED_BRIGHT, RED_DARK)
def icon_stamina_potion(): _draw_potion("stamina_potion", LEAF_BRIGHT, LEAF_DARK)
def icon_antidote_potion(): _draw_potion("antidote_potion", LEAF_LIGHT, LEAF_DARK)
def icon_mana_potion(): _draw_potion("mana_potion", PURPLE_BRIGHT, PURPLE_DARK)
def icon_fire_resistance_potion(): _draw_potion("fire_resistance_potion", ORANGE_BRIGHT, ORANGE_DARK)
def icon_frost_resistance_potion(): _draw_potion("frost_resistance_potion", CYAN_BRIGHT, CYAN_DARK)
def icon_speed_potion(): _draw_potion("speed_potion", GOLD_BRIGHT, GOLD_DARK)


def icon_bandage():
    s, c = make_surface()
    # Rolled bandage
    c.set_line_width(8)
    sc(c, WHITE, 0.9)
    c.arc(32, 32, 14, 0, 1.8 * math.pi)
    c.stroke()
    # Cross
    sc(c, RED_MED)
    rounded_rect(c, 28, 22, 8, 20, 2)
    c.fill()
    rounded_rect(c, 22, 28, 20, 8, 2)
    sc(c, RED_MED)
    c.fill()
    save_icon(s, "bandage")


# ── TOOL ICONS ───────────────────────────────────────────────────────────────

def icon_hammer():
    s, c = make_surface()
    # Handle
    handle(c, 32, 40, 28, 6, BARK_LIGHT, BARK_DARK, -0.3)
    # Head
    c.save()
    c.translate(24, 22)
    c.rotate(-0.3)
    rounded_rect(c, -14, -8, 28, 16, 3)
    pat = cairo.LinearGradient(-14, -8, 14, 8)
    pat.add_color_stop_rgb(0, *STONE_LIGHT)
    pat.add_color_stop_rgb(1, *STONE_DARK)
    c.set_source(pat)
    c.fill()
    c.restore()
    save_icon(s, "hammer")


def icon_torch():
    s, c = make_surface()
    # Stick
    handle(c, 32, 38, 30, 5, BARK_LIGHT, BARK_DARK)
    # Flame
    c.move_to(32, 8)
    c.curve_to(38, 14, 40, 20, 36, 24)
    c.curve_to(34, 26, 30, 26, 28, 24)
    c.curve_to(24, 20, 26, 14, 32, 8)
    c.close_path()
    pat = cairo.RadialGradient(32, 18, 2, 32, 18, 10)
    pat.add_color_stop_rgb(0, *GOLD_BRIGHT)
    pat.add_color_stop_rgb(0.5, *ORANGE_BRIGHT)
    pat.add_color_stop_rgb(1, *RED_MED)
    c.set_source(pat)
    c.fill()
    save_icon(s, "torch")


def icon_stone_pickaxe():
    s, c = make_surface()
    # Handle
    handle(c, 32, 38, 28, 5, BARK_LIGHT, BARK_DARK, -0.2)
    # Pick head
    c.save()
    c.translate(26, 22)
    c.rotate(-0.2)
    c.move_to(-18, -2)
    c.line_to(18, -8)
    c.line_to(20, -4)
    c.line_to(-2, 4)
    c.line_to(-16, 4)
    c.close_path()
    sc(c, STONE_LIGHT)
    c.fill()
    c.restore()
    save_icon(s, "stone_pickaxe")


def icon_stone_hoe():
    s, c = make_surface()
    # Handle
    handle(c, 32, 38, 30, 5, BARK_LIGHT, BARK_DARK)
    # Hoe blade
    c.move_to(20, 18)
    c.line_to(44, 18)
    c.line_to(44, 26)
    c.line_to(20, 26)
    c.close_path()
    sc(c, STONE_LIGHT)
    c.fill()
    save_icon(s, "stone_hoe")


# ── WEAPON ICONS ─────────────────────────────────────────────────────────────

def icon_fists():
    s, c = make_surface()
    # Fist shape
    rcircle(c, 32, 32, 18, BLUE_LIGHT, BLUE_DARK)
    # Finger lines
    c.set_line_width(1.5)
    sc(c, BLUE_DARK, 0.5)
    for y in [26, 30, 34]:
        c.move_to(22, y)
        c.line_to(42, y)
        c.stroke()
    save_icon(s, "fists")


def icon_club():
    s, c = make_surface()
    # Thick club
    c.move_to(24, 52)
    c.line_to(20, 14)
    c.curve_to(18, 8, 46, 8, 44, 14)
    c.line_to(40, 52)
    c.close_path()
    pat = cairo.LinearGradient(20, 8, 44, 52)
    pat.add_color_stop_rgb(0, *BARK_LIGHT)
    pat.add_color_stop_rgb(1, *BARK_DARK)
    c.set_source(pat)
    c.fill()
    # Wood grain
    c.set_line_width(0.8)
    sc(c, BARK_SHADOW, 0.3)
    for y in [18, 26, 34, 42]:
        c.move_to(24, y)
        c.line_to(40, y)
        c.stroke()
    save_icon(s, "club")


def _draw_sword(name, blade_top, blade_bot, guard_color):
    s, c = make_surface()
    # Blade
    blade(c, 32, 22, 32, 8, blade_top, blade_bot, -0.15)
    # Guard
    c.save()
    c.translate(32, 38)
    c.rotate(-0.15)
    rounded_rect(c, -10, -3, 20, 6, 2)
    sc(c, guard_color)
    c.fill()
    c.restore()
    # Handle
    handle(c, 34, 48, 14, 5, BARK_LIGHT, BARK_DARK, -0.15)
    # Pommel
    circle(c, 35, 54, 3, guard_color)
    save_icon(s, name)

def icon_stone_sword(): _draw_sword("stone_sword", STONE_LIGHT, STONE_DARK, GOLD_DARK)
def icon_iron_sword(): _draw_sword("iron_sword", IRON_LIGHT, IRON_DARK, GOLD_PRIMARY)


def _draw_axe(name, head_color1, head_color2):
    s, c = make_surface()
    # Handle
    handle(c, 30, 36, 32, 5, BARK_LIGHT, BARK_DARK, -0.2)
    # Axe head
    c.save()
    c.translate(24, 20)
    c.rotate(-0.2)
    c.move_to(-4, -10)
    c.curve_to(-18, -6, -18, 10, -4, 14)
    c.line_to(4, 10)
    c.line_to(4, -6)
    c.close_path()
    pat = cairo.LinearGradient(-18, -10, 4, 14)
    pat.add_color_stop_rgb(0, *head_color1)
    pat.add_color_stop_rgb(1, *head_color2)
    c.set_source(pat)
    c.fill()
    c.restore()
    save_icon(s, name)

def icon_stone_axe(): _draw_axe("stone_axe", STONE_LIGHT, STONE_DARK)
def icon_iron_axe(): _draw_axe("iron_axe", IRON_LIGHT, IRON_DARK)
def icon_iron_pickaxe():
    s, c = make_surface()
    handle(c, 32, 38, 28, 5, BARK_LIGHT, BARK_DARK, -0.2)
    c.save()
    c.translate(26, 22)
    c.rotate(-0.2)
    c.move_to(-18, -2)
    c.line_to(18, -8)
    c.line_to(20, -4)
    c.line_to(-2, 4)
    c.line_to(-16, 4)
    c.close_path()
    pat = cairo.LinearGradient(-18, -8, 20, 4)
    pat.add_color_stop_rgb(0, *IRON_LIGHT)
    pat.add_color_stop_rgb(1, *IRON_DARK)
    c.set_source(pat)
    c.fill()
    c.restore()
    save_icon(s, "iron_pickaxe")


def icon_stone_knife():
    s, c = make_surface()
    # Short blade
    blade(c, 32, 24, 22, 6, STONE_LIGHT, STONE_DARK, -0.2)
    # Handle
    handle(c, 34, 44, 14, 5, BARK_LIGHT, BARK_DARK, -0.2)
    save_icon(s, "stone_knife")


def icon_bow():
    s, c = make_surface()
    # Bow curve
    c.set_line_width(4)
    sc(c, BARK_LIGHT)
    c.arc(42, 32, 22, math.pi * 0.6, math.pi * 1.4)
    c.stroke()
    # String
    c.set_line_width(1.5)
    sc(c, WHITE, 0.7)
    c.move_to(27, 14)
    c.line_to(27, 50)
    c.stroke()
    save_icon(s, "bow")


def _draw_wand(name, orb_color1, orb_color2):
    s, c = make_surface()
    # Stick
    handle(c, 32, 36, 30, 4, BARK_LIGHT, BARK_DARK, -0.1)
    # Orb at top
    rcircle(c, 30, 16, 8, orb_color1, orb_color2)
    circle(c, 27, 13, 2.5, WHITE, 0.5)
    save_icon(s, name)

def icon_fire_wand(): _draw_wand("fire_wand", ORANGE_BRIGHT, RED_DARK)
def icon_lightning_wand(): _draw_wand("lightning_wand", GOLD_BRIGHT, BLUE_LIGHT)
def icon_arcane_wand(): _draw_wand("arcane_wand", PURPLE_BRIGHT, PURPLE_DARK)


# ── SHIELD ICONS ─────────────────────────────────────────────────────────────

def _draw_shield(name, color1, color2, emblem_color=None):
    s, c = make_surface()
    # Shield shape
    c.move_to(32, 8)
    c.curve_to(52, 10, 56, 28, 50, 44)
    c.curve_to(44, 54, 32, 58, 32, 58)
    c.curve_to(32, 58, 20, 54, 14, 44)
    c.curve_to(8, 28, 12, 10, 32, 8)
    c.close_path()
    pat = cairo.LinearGradient(8, 8, 56, 58)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    c.set_source(pat)
    c.fill()
    # Border
    c.move_to(32, 8)
    c.curve_to(52, 10, 56, 28, 50, 44)
    c.curve_to(44, 54, 32, 58, 32, 58)
    c.curve_to(32, 58, 20, 54, 14, 44)
    c.curve_to(8, 28, 12, 10, 32, 8)
    c.close_path()
    c.set_line_width(2)
    sc(c, GOLD_PRIMARY)
    c.stroke()
    # Emblem
    if emblem_color:
        circle(c, 32, 32, 8, emblem_color, 0.6)
    save_icon(s, name)

def icon_tower_shield(): _draw_shield("tower_shield", IRON_LIGHT, IRON_DARK, GOLD_PRIMARY)
def icon_round_shield(): _draw_shield("round_shield", BARK_LIGHT, BARK_DARK, BLUE_LIGHT)
def icon_buckler(): _draw_shield("buckler", STONE_LIGHT, STONE_DARK, None)


# ── ARMOR ICONS ──────────────────────────────────────────────────────────────

def _draw_helmet(name, color1, color2):
    s, c = make_surface()
    # Helmet dome
    c.arc(32, 32, 20, math.pi, 2 * math.pi)
    c.line_to(52, 48)
    c.line_to(12, 48)
    c.close_path()
    pat = cairo.LinearGradient(12, 12, 52, 48)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    c.set_source(pat)
    c.fill()
    # Eye slit
    rounded_rect(c, 20, 36, 24, 4, 2)
    sc(c, (0.02, 0.02, 0.05))
    c.fill()
    save_icon(s, name)


def _draw_chest(name, color1, color2):
    s, c = make_surface()
    # Chestplate shape
    c.move_to(16, 12)
    c.line_to(48, 12)
    c.line_to(52, 20)
    c.line_to(48, 54)
    c.line_to(16, 54)
    c.line_to(12, 20)
    c.close_path()
    pat = cairo.LinearGradient(12, 12, 52, 54)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    c.set_source(pat)
    c.fill()
    # Center line
    c.set_line_width(1.5)
    sc(c, color2, 0.5)
    c.move_to(32, 14)
    c.line_to(32, 52)
    c.stroke()
    save_icon(s, name)


def _draw_pants(name, color1, color2):
    s, c = make_surface()
    # Pants shape (two legs)
    c.move_to(16, 10)
    c.line_to(48, 10)
    c.line_to(46, 32)
    c.line_to(50, 54)
    c.line_to(36, 54)
    c.line_to(32, 36)
    c.line_to(28, 54)
    c.line_to(14, 54)
    c.line_to(18, 32)
    c.close_path()
    pat = cairo.LinearGradient(14, 10, 50, 54)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    c.set_source(pat)
    c.fill()
    save_icon(s, name)


def _draw_cape(name, color1, color2):
    s, c = make_surface()
    # Cape shape
    c.move_to(18, 10)
    c.line_to(46, 10)
    c.curve_to(50, 30, 48, 48, 44, 56)
    c.curve_to(38, 54, 26, 54, 20, 56)
    c.curve_to(16, 48, 14, 30, 18, 10)
    c.close_path()
    pat = cairo.LinearGradient(14, 10, 50, 56)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    c.set_source(pat)
    c.fill()
    # Clasp
    circle(c, 32, 12, 4, GOLD_PRIMARY)
    save_icon(s, name)


def _draw_boots(name, color1, color2):
    s, c = make_surface()
    # Boot shape
    c.move_to(12, 16)
    c.line_to(30, 16)
    c.line_to(30, 38)
    c.line_to(52, 42)
    c.line_to(52, 52)
    c.line_to(10, 52)
    c.line_to(12, 38)
    c.close_path()
    pat = cairo.LinearGradient(10, 16, 52, 52)
    pat.add_color_stop_rgb(0, *color1)
    pat.add_color_stop_rgb(1, *color2)
    c.set_source(pat)
    c.fill()
    save_icon(s, name)


# Pig armor
def icon_pig_helmet(): _draw_helmet("pig_helmet", PINK_BRIGHT, PINK_DARK)
def icon_pig_chest(): _draw_chest("pig_chest", PINK_BRIGHT, PINK_DARK)
def icon_pig_pants(): _draw_pants("pig_pants", PINK_BRIGHT, PINK_DARK)
def icon_pig_cape(): _draw_cape("pig_cape", PINK_BRIGHT, PINK_DARK)

# Deer armor
def icon_deer_helmet(): _draw_helmet("deer_helmet", LEATHER_LIGHT, LEATHER_DARK)
def icon_deer_chest(): _draw_chest("deer_chest", LEATHER_LIGHT, LEATHER_DARK)
def icon_deer_pants(): _draw_pants("deer_pants", LEATHER_LIGHT, LEATHER_DARK)
def icon_deer_cape(): _draw_cape("deer_cape", LEATHER_LIGHT, LEATHER_DARK)

# Bone armor
def icon_bone_armor_helmet(): _draw_helmet("bone_armor_helmet", BONE_LIGHT, BONE_DARK)
def icon_bone_armor_chest(): _draw_chest("bone_armor_chest", BONE_LIGHT, BONE_DARK)
def icon_bone_armor_legs(): _draw_pants("bone_armor_legs", BONE_LIGHT, BONE_DARK)
def icon_bone_armor_boots(): _draw_boots("bone_armor_boots", BONE_LIGHT, BONE_DARK)

# Tank armor
def icon_tank_helmet(): _draw_helmet("tank_helmet", IRON_LIGHT, IRON_DARK)
def icon_tank_chest(): _draw_chest("tank_chest", IRON_LIGHT, IRON_DARK)
def icon_tank_pants(): _draw_pants("tank_pants", IRON_LIGHT, IRON_DARK)
def icon_tank_cape(): _draw_cape("tank_cape", IRON_LIGHT, IRON_DARK)


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

ALL_ICONS = [
    # Resources
    ("wood", icon_wood),
    ("stone", icon_stone),
    ("earth", icon_earth),
    ("resin", icon_resin),
    ("iron", icon_iron),
    ("copper", icon_copper),
    ("plant_fiber", icon_plant_fiber),
    ("rope", icon_rope),
    ("arrows", icon_arrows),
    ("charcoal", icon_charcoal),
    ("bone", icon_bone),
    ("rotten_flesh", icon_rotten_flesh),
    ("glowing_spore", icon_glowing_spore),
    ("fungal_essence", icon_fungal_essence),
    ("pig_leather", icon_pig_leather),
    ("deer_leather", icon_deer_leather),
    # Raw meat
    ("raw_venison", icon_raw_venison),
    ("raw_pork", icon_raw_pork),
    ("raw_mutton", icon_raw_mutton),
    # Raw foods
    ("pinkberry", icon_pinkberry),
    ("rootbeer", icon_rootbeer),
    ("rootbeer_seed", icon_rootbeer_seed),
    ("dark_mushroom", icon_dark_mushroom),
    ("nightshade_berry", icon_nightshade_berry),
    ("truffle", icon_truffle),
    ("swamp_root", icon_swamp_root),
    ("frost_berry", icon_frost_berry),
    ("prickly_fruit", icon_prickly_fruit),
    ("mana_fruit", icon_mana_fruit),
    ("ember_pepper", icon_ember_pepper),
    # Seeds
    ("fungal_seed", icon_fungal_seed),
    ("lotus_seed", icon_lotus_seed),
    ("ice_crystal_seed", icon_ice_crystal_seed),
    ("sun_seed", icon_sun_seed),
    ("ash_seed", icon_ash_seed),
    ("crystal_seed", icon_crystal_seed),
    # Herbs
    ("marsh_herb", icon_marsh_herb),
    ("alpine_herb", icon_alpine_herb),
    ("desert_sage", icon_desert_sage),
    ("arcane_herb", icon_arcane_herb),
    ("brimstone_root", icon_brimstone_root),
    # Cooked food
    ("cooked_venison", icon_cooked_venison),
    ("cooked_pork", icon_cooked_pork),
    ("cooked_mutton", icon_cooked_mutton),
    ("cooked_rootbeer", icon_cooked_rootbeer),
    ("cooked_truffle", icon_cooked_truffle),
    ("cooked_frost_berry", icon_cooked_frost_berry),
    ("cooked_prickly_fruit", icon_cooked_prickly_fruit),
    ("cooked_mana_fruit", icon_cooked_mana_fruit),
    ("cooked_ember_pepper", icon_cooked_ember_pepper),
    # Potions
    ("healing_potion", icon_healing_potion),
    ("stamina_potion", icon_stamina_potion),
    ("antidote_potion", icon_antidote_potion),
    ("mana_potion", icon_mana_potion),
    ("fire_resistance_potion", icon_fire_resistance_potion),
    ("frost_resistance_potion", icon_frost_resistance_potion),
    ("speed_potion", icon_speed_potion),
    ("bandage", icon_bandage),
    # Tools
    ("hammer", icon_hammer),
    ("torch", icon_torch),
    ("stone_pickaxe", icon_stone_pickaxe),
    ("stone_hoe", icon_stone_hoe),
    # Weapons
    ("fists", icon_fists),
    ("club", icon_club),
    ("stone_sword", icon_stone_sword),
    ("iron_sword", icon_iron_sword),
    ("stone_axe", icon_stone_axe),
    ("iron_axe", icon_iron_axe),
    ("iron_pickaxe", icon_iron_pickaxe),
    ("stone_knife", icon_stone_knife),
    ("bow", icon_bow),
    ("fire_wand", icon_fire_wand),
    ("lightning_wand", icon_lightning_wand),
    ("arcane_wand", icon_arcane_wand),
    # Shields
    ("tower_shield", icon_tower_shield),
    ("round_shield", icon_round_shield),
    ("buckler", icon_buckler),
    # Armor - Pig
    ("pig_helmet", icon_pig_helmet),
    ("pig_chest", icon_pig_chest),
    ("pig_pants", icon_pig_pants),
    ("pig_cape", icon_pig_cape),
    # Armor - Deer
    ("deer_helmet", icon_deer_helmet),
    ("deer_chest", icon_deer_chest),
    ("deer_pants", icon_deer_pants),
    ("deer_cape", icon_deer_cape),
    # Armor - Bone
    ("bone_armor_helmet", icon_bone_armor_helmet),
    ("bone_armor_chest", icon_bone_armor_chest),
    ("bone_armor_legs", icon_bone_armor_legs),
    ("bone_armor_boots", icon_bone_armor_boots),
    # Armor - Tank
    ("tank_helmet", icon_tank_helmet),
    ("tank_chest", icon_tank_chest),
    ("tank_pants", icon_tank_pants),
    ("tank_cape", icon_tank_cape),
]


if __name__ == "__main__":
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Generating {len(ALL_ICONS)} item icons to {OUTPUT_DIR}/")
    for name, func in ALL_ICONS:
        func()
    print(f"\nDone! Generated {len(ALL_ICONS)} icons.")
