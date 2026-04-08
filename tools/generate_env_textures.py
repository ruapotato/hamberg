#!/usr/bin/env python3
"""
Generate vector-art environment sprites (trees, bushes, rocks, grass) using pycairo.
Outputs PNGs to assets/textures/environment/ for the game's texture override system.

Color palette: 4-color Hollow Knight style
  Blue (#0014ff) — environment base (terrain, sky, trees, rocks, grass)
  Yellow (#ffeb00) — highlights, loot, interactive elements, golden accents, enemies
  Pink (#ff0093) — magic, special effects, rare/dangerous items, spells
  Green (#00ff6c) — nature, healing, growth, health bars, friendly indicators

Usage: python3 tools/generate_env_textures.py
"""

import cairo
import math
import random
import struct
from pathlib import Path
from PIL import Image
import io

# Deterministic for reproducible output
random.seed(42)

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "textures" / "environment"

# ── 4-color palette — Hollow Knight style ──────────────────────────────────
# Foliage: shades of blue (environment base)
LEAF_BRIGHT  = (0.55, 0.65, 0.95)   # Brightest blue (leaf highlights)
LEAF_LIGHT   = (0.35, 0.48, 0.85)   # Light blue leaves
LEAF_MED     = (0.20, 0.35, 0.72)   # Medium blue leaves
LEAF_DARK    = (0.10, 0.20, 0.55)   # Dark blue leaves
LEAF_SHADOW  = (0.05, 0.10, 0.38)   # Deepest shadow blue

# Trunks: blue bark
BARK_LIGHT   = (0.25, 0.30, 0.52)   # Light blue bark
BARK_MED     = (0.15, 0.20, 0.42)   # Medium blue bark
BARK_DARK    = (0.08, 0.12, 0.30)   # Dark blue bark
BARK_SHADOW  = (0.04, 0.06, 0.20)   # Near-black blue bark

# Primary Blue spectrum (#0014ff)
BLUE_BRIGHT = (0.45, 0.52, 1.0)
BLUE_MED = (0.0, 0.08, 1.0)         # #0014ff
BLUE_DARK = (0.0, 0.04, 0.5)

# Secondary Yellow spectrum (#ffeb00)
YELLOW_BRIGHT = (1.0, 0.97, 0.6)
YELLOW_MED = (1.0, 0.92, 0.0)       # #ffeb00
YELLOW_DARK = (0.5, 0.46, 0.0)

# Accent Pink spectrum (#ff0093)
PINK_BRIGHT = (1.0, 0.55, 0.8)
PINK_MED = (1.0, 0.0, 0.576)        # #ff0093
PINK_DARK = (0.5, 0.0, 0.29)

# Accent Green spectrum (#00ff6c)
GREEN_BRIGHT = (0.5, 1.0, 0.75)
GREEN_MED = (0.0, 1.0, 0.424)       # #00ff6c
GREEN_DARK = (0.0, 0.5, 0.21)

# Gold accents (for highlights, loot, interactive) — mapped to Yellow
GOLD_BRIGHT  = YELLOW_BRIGHT
GOLD_PRIMARY = YELLOW_MED
GOLD_DARK    = YELLOW_DARK
GOLD_METAL   = (1.0, 0.97, 0.7)     # Metallic highlight
GOLD_LIGHT   = YELLOW_BRIGHT
GOLD_SPEC    = (1.0, 1.0, 0.85)     # Specular white-gold

# Backward-compat aliases used throughout drawing code
GREEN_YELLOW = LEAF_BRIGHT           # Tips are bright blue now
BROWN_DARK   = BARK_DARK
BROWN_MED    = BARK_MED
BROWN_LIGHT  = BARK_LIGHT
BROWN_BARK   = BARK_DARK
BLUE_PRIMARY = (0.0, 0.08, 1.0)     # #0014ff
BLUE_LIGHT   = (0.45, 0.55, 1.0)

# Misc — also blue-tinted
WHITE      = (0.9, 0.92, 1.0)       # Blue-white
SNOW       = (0.85, 0.9, 1.0)
GRAY_LIGHT = (0.5, 0.52, 0.65)      # Blue-gray
GRAY_MED   = (0.3, 0.32, 0.45)
GRAY_DARK  = (0.15, 0.17, 0.28)


# ── Helpers ──────────────────────────────────────────────────────────────────

def make_surface(w: int, h: int):
    """Create a cairo ARGB32 surface and context with best antialiasing."""
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surface)
    ctx.set_antialias(cairo.ANTIALIAS_BEST)
    ctx.set_operator(cairo.OPERATOR_OVER)
    # Clear to transparent
    ctx.set_source_rgba(0, 0, 0, 0)
    ctx.set_operator(cairo.OPERATOR_SOURCE)
    ctx.paint()
    ctx.set_operator(cairo.OPERATOR_OVER)
    return surface, ctx


def save_surface(surface: cairo.ImageSurface, filename: str):
    """Convert ARGB32 surface to RGBA PNG via Pillow."""
    w, h = surface.get_width(), surface.get_height()
    buf = surface.get_data()
    # Cairo ARGB32 is BGRA in memory on little-endian
    img = Image.frombuffer("RGBA", (w, h), bytes(buf), "raw", "BGRA", 0, 1)
    path = OUTPUT_DIR / filename
    img.save(str(path), "PNG")
    print(f"  Saved {path}")


def set_color(ctx, rgb, alpha=1.0):
    ctx.set_source_rgba(*rgb, alpha)


def draw_circle(ctx, cx, cy, r, rgb, alpha=1.0):
    ctx.arc(cx, cy, r, 0, 2 * math.pi)
    set_color(ctx, rgb, alpha)
    ctx.fill()


def draw_radial_circle(ctx, cx, cy, r, inner_rgb, outer_rgb, inner_a=1.0, outer_a=1.0,
                        highlight_offset=(-0.25, -0.25)):
    """Draw a circle with radial gradient, light source from upper-left."""
    pat = cairo.RadialGradient(
        cx + r * highlight_offset[0], cy + r * highlight_offset[1], r * 0.05,
        cx, cy, r
    )
    pat.add_color_stop_rgba(0, *inner_rgb, inner_a)
    pat.add_color_stop_rgba(1, *outer_rgb, outer_a)
    ctx.arc(cx, cy, r, 0, 2 * math.pi)
    ctx.set_source(pat)
    ctx.fill()


def draw_trunk_gradient(ctx, x, y, w, h, top_rgb, bot_rgb):
    """Draw a tapered trunk with linear gradient."""
    pat = cairo.LinearGradient(x, y, x, y + h)
    pat.add_color_stop_rgb(0, *top_rgb)
    pat.add_color_stop_rgb(1, *bot_rgb)
    # Slight taper: top is slightly narrower
    taper = w * 0.12
    ctx.move_to(x + taper, y)
    ctx.line_to(x + w - taper, y)
    ctx.line_to(x + w, y + h)
    ctx.line_to(x, y + h)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()


def draw_wood_grain(ctx, x, y, w, h, color, count=6):
    """Draw subtle wood grain lines on a trunk area."""
    ctx.set_line_width(0.8)
    set_color(ctx, color, 0.3)
    for i in range(count):
        yy = y + h * (i + 1) / (count + 1) + random.uniform(-2, 2)
        ctx.move_to(x + 2, yy)
        ctx.line_to(x + w - 2, yy)
        ctx.stroke()


def draw_bark_texture(ctx, x, y, w, h, color, count=12):
    """Draw bark texture dots/dashes."""
    ctx.set_line_width(1.0)
    for _ in range(count):
        bx = x + random.uniform(3, w - 3)
        by = y + random.uniform(3, h - 3)
        ctx.move_to(bx, by)
        ctx.line_to(bx + random.uniform(-3, 3), by + random.uniform(1, 4))
        set_color(ctx, color, random.uniform(0.15, 0.35))
        ctx.stroke()


# ── Tree generators ─────────────────────────────────────────────────────────

def generate_oak(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Trunk ──
    trunk_w, trunk_h = 40, 200
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 20
    draw_trunk_gradient(ctx, trunk_x, trunk_y, trunk_w, trunk_h,
                        BROWN_MED, BROWN_DARK)
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, BROWN_DARK)
    draw_bark_texture(ctx, trunk_x, trunk_y, trunk_w, trunk_h, BROWN_DARK)

    # Small root flare
    for side in [-1, 1]:
        ctx.move_to(cx + side * trunk_w / 2, cy_base - 20)
        ctx.curve_to(cx + side * (trunk_w / 2 + 18), cy_base - 10,
                     cx + side * (trunk_w / 2 + 22), cy_base - 2,
                     cx + side * (trunk_w / 2 + 10), cy_base)
        ctx.line_to(cx + side * trunk_w / 2, cy_base - 20)
        ctx.close_path()
        set_color(ctx, BROWN_DARK)
        ctx.fill()

    # ── Canopy ──
    canopy_cy = trunk_y - 10
    # Shadow layer first (offset right and down)
    blobs = [
        (cx, canopy_cy, 72),
        (cx - 55, canopy_cy + 15, 55),
        (cx + 55, canopy_cy + 15, 55),
        (cx - 30, canopy_cy - 40, 50),
        (cx + 30, canopy_cy - 40, 50),
        (cx, canopy_cy - 60, 45),
        (cx - 15, canopy_cy + 35, 48),
        (cx + 15, canopy_cy + 35, 48),
    ]
    # Shadow
    for bx, by, br in blobs:
        draw_circle(ctx, bx + 6, by + 6, br, (0.03, 0.06, 0.18), 0.35)
    # Main canopy with radial gradients (blue)
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_LIGHT, LEAF_DARK)
    # Highlight layer (upper-left blobs brighter)
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx - 8, by - 8, br * 0.5,
                           LEAF_BRIGHT, LEAF_LIGHT, 0.6, 0.0)
    # Leaf detail dots (blue shades)
    for _ in range(40):
        dx = cx + random.gauss(0, 50)
        dy = canopy_cy + random.gauss(0, 45)
        dr = random.uniform(3, 8)
        c = random.choice([LEAF_BRIGHT, LEAF_LIGHT, LEAF_MED])
        draw_circle(ctx, dx, dy, dr, c, random.uniform(0.3, 0.6))

    # Gold accent: fruit dots
    for _ in range(5):
        dx = cx + random.gauss(0, 40)
        dy = canopy_cy + random.gauss(-20, 30)
        draw_circle(ctx, dx, dy, 2, GOLD_PRIMARY, 0.5)

    save_surface(surface, "tree_oak_front.png")


def generate_pine(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Trunk ──
    trunk_w, trunk_h = 22, 180
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 15
    draw_trunk_gradient(ctx, trunk_x, trunk_y, trunk_w, trunk_h,
                        BROWN_MED, BROWN_DARK)
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, BROWN_DARK, 4)

    # ── Canopy: stacked triangles ──
    layers = [
        (cy_base - 170, 100, 70),   # bottom: y, half-width, height
        (cy_base - 230, 82, 70),
        (cy_base - 280, 64, 65),
        (cy_base - 325, 48, 60),
        (cy_base - 365, 32, 55),
    ]
    for i, (ly, lw, lh) in enumerate(layers):
        # Shadow
        ctx.move_to(cx + 4, ly - lh + 4)
        ctx.line_to(cx + lw + 4, ly + 4)
        ctx.line_to(cx - lw + 4, ly + 4)
        ctx.close_path()
        set_color(ctx, (0.02, 0.04, 0.15), 0.3)
        ctx.fill()
        # Triangle with gradient (blue)
        pat = cairo.LinearGradient(cx, ly - lh, cx, ly)
        pat.add_color_stop_rgb(0, *LEAF_LIGHT)
        pat.add_color_stop_rgb(0.4, *LEAF_DARK)
        pat.add_color_stop_rgb(1, *LEAF_SHADOW)
        ctx.move_to(cx, ly - lh)
        ctx.line_to(cx + lw, ly)
        ctx.line_to(cx - lw, ly)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()
        # Lighter tips (edges)
        ctx.set_line_width(2.0)
        ctx.move_to(cx, ly - lh)
        ctx.line_to(cx + lw, ly)
        set_color(ctx, LEAF_BRIGHT, 0.4)
        ctx.stroke()
        ctx.move_to(cx, ly - lh)
        ctx.line_to(cx - lw, ly)
        set_color(ctx, LEAF_BRIGHT, 0.3)
        ctx.stroke()
        # Snow on top layers
        if i >= 2:
            ctx.move_to(cx, ly - lh)
            ctx.line_to(cx + lw * 0.5, ly - lh + lh * 0.25)
            ctx.line_to(cx - lw * 0.5, ly - lh + lh * 0.25)
            ctx.close_path()
            set_color(ctx, SNOW, 0.6 + i * 0.05)
            ctx.fill()

    # Star/blue accent at top
    draw_circle(ctx, cx, layers[-1][0] - layers[-1][2] - 3, 4, BLUE_LIGHT, 0.6)

    save_surface(surface, "tree_pine_front.png")


def generate_dead(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Gnarled trunk ──
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    # Main trunk: twisted curve
    trunk_bot = cy_base - 20
    trunk_top = cy_base - 300

    # Draw thick trunk with curve (dark blue bark)
    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, *BARK_MED)
    pat.add_color_stop_rgb(1, *BARK_SHADOW)

    ctx.move_to(cx - 18, trunk_bot)
    ctx.curve_to(cx - 22, trunk_bot - 100, cx + 15, trunk_bot - 180, cx - 5, trunk_top)
    ctx.line_to(cx + 12, trunk_top + 5)
    ctx.curve_to(cx + 25, trunk_bot - 170, cx - 10, trunk_bot - 90, cx + 18, trunk_bot)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Bark cracks (dark blue)
    ctx.set_line_width(1.2)
    for _ in range(8):
        by = random.uniform(trunk_top + 30, trunk_bot - 30)
        bx = cx + random.uniform(-12, 12)
        ctx.move_to(bx, by)
        ctx.line_to(bx + random.uniform(-5, 5), by + random.uniform(8, 20))
        set_color(ctx, (0.02, 0.04, 0.12), 0.5)
        ctx.stroke()

    # ── Branches ──
    branches = [
        (cx - 5, trunk_top + 40, cx - 80, trunk_top - 30, cx - 100, trunk_top - 50),
        (cx + 8, trunk_top + 30, cx + 70, trunk_top - 40, cx + 110, trunk_top - 20),
        (cx - 2, trunk_top + 80, cx - 60, trunk_top + 20, cx - 90, trunk_top + 40),
        (cx + 5, trunk_top + 90, cx + 55, trunk_top + 30, cx + 85, trunk_top + 60),
    ]
    for x0, y0, cx1, cy1, x1, y1 in branches:
        ctx.set_line_width(random.uniform(4, 8))
        ctx.move_to(x0, y0)
        ctx.curve_to(cx1 * 0.6 + x0 * 0.4, cy1 * 0.6 + y0 * 0.4,
                     cx1, cy1, x1, y1)
        set_color(ctx, GRAY_MED)
        ctx.stroke()
        # Sub-branch
        ctx.set_line_width(2.5)
        ctx.move_to(x1, y1)
        ctx.curve_to(x1 + random.uniform(-20, 20), y1 - 20,
                     x1 + random.uniform(-30, 30), y1 - 35,
                     x1 + random.uniform(-25, 25), y1 - 45)
        set_color(ctx, GRAY_MED)
        ctx.stroke()

    # Root gnarls at base
    for side in [-1, 1]:
        ctx.set_line_width(6)
        ctx.move_to(cx + side * 16, trunk_bot)
        ctx.curve_to(cx + side * 35, trunk_bot + 5,
                     cx + side * 45, trunk_bot - 5,
                     cx + side * 50, trunk_bot + 2)
        set_color(ctx, BARK_SHADOW)
        ctx.stroke()

    save_surface(surface, "tree_dead_front.png")


def generate_magic(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Purple-blue trunk with glow ──
    trunk_w, trunk_h = 30, 190
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 20

    # Glow halo behind trunk (bright blue glow)
    glow = cairo.RadialGradient(cx, trunk_y + trunk_h / 2, trunk_w / 2,
                                cx, trunk_y + trunk_h / 2, trunk_w * 2)
    glow.add_color_stop_rgba(0, *LEAF_BRIGHT, 0.25)
    glow.add_color_stop_rgba(1, *LEAF_MED, 0.0)
    ctx.rectangle(cx - trunk_w * 2, trunk_y - 20, trunk_w * 4, trunk_h + 40)
    ctx.set_source(glow)
    ctx.fill()

    # Trunk (glowing blue)
    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, *LEAF_BRIGHT)
    pat.add_color_stop_rgb(1, *LEAF_MED)
    taper = trunk_w * 0.1
    ctx.move_to(trunk_x + taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w - taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w, trunk_y + trunk_h)
    ctx.line_to(trunk_x, trunk_y + trunk_h)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, LEAF_DARK, 5)

    # ── Canopy: blue circles ──
    canopy_cy = trunk_y - 20
    blobs = [
        (cx, canopy_cy, 65),
        (cx - 48, canopy_cy + 12, 48),
        (cx + 48, canopy_cy + 12, 48),
        (cx - 25, canopy_cy - 38, 45),
        (cx + 25, canopy_cy - 38, 45),
        (cx, canopy_cy - 55, 40),
    ]
    # Glow behind canopy (bright blue)
    glow2 = cairo.RadialGradient(cx, canopy_cy, 20, cx, canopy_cy, 100)
    glow2.add_color_stop_rgba(0, *LEAF_BRIGHT, 0.3)
    glow2.add_color_stop_rgba(1, *LEAF_MED, 0.0)
    ctx.arc(cx, canopy_cy, 110, 0, 2 * math.pi)
    ctx.set_source(glow2)
    ctx.fill()

    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_LIGHT, LEAF_DARK)
    # Lighter inner glow
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx - 5, by - 5, br * 0.4,
                           LEAF_BRIGHT, LEAF_LIGHT, 0.5, 0.0)

    # Sparkle dots (blue-white)
    for _ in range(25):
        dx = cx + random.gauss(0, 45)
        dy = canopy_cy + random.gauss(0, 40)
        dr = random.uniform(1.5, 3.5)
        draw_circle(ctx, dx, dy, dr, WHITE, random.uniform(0.5, 0.95))
    # Pink magical sparkles (accent)
    for _ in range(8):
        dx = cx + random.gauss(0, 55)
        dy = canopy_cy + random.gauss(0, 50)
        draw_circle(ctx, dx, dy, random.uniform(2, 4), PINK_BRIGHT, random.uniform(0.3, 0.7))
    # Extra pink glow sparkles
    for _ in range(5):
        dx = cx + random.gauss(0, 45)
        dy = canopy_cy + random.gauss(0, 40)
        draw_circle(ctx, dx, dy, random.uniform(1.5, 3), PINK_MED, random.uniform(0.2, 0.5))

    save_surface(surface, "tree_magic_front.png")


def generate_palm(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Curved trunk ──
    trunk_bot = cy_base - 20
    trunk_top = cy_base - 340

    # S-curve trunk (blue bark)
    ctx.set_line_width(24)
    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, *BARK_LIGHT)
    pat.add_color_stop_rgb(1, *BARK_DARK)

    ctx.move_to(cx + 10, trunk_bot)
    ctx.curve_to(cx + 25, trunk_bot - 100,
                 cx - 20, trunk_bot - 200,
                 cx - 5, trunk_top)
    ctx.set_source(pat)
    ctx.stroke()

    # Ring texture on trunk
    ctx.set_line_width(1.5)
    steps = 18
    for i in range(steps):
        t = i / steps
        # Approximate point along the curve
        tt = 1 - t
        bx = tt**3 * (cx + 10) + 3*tt**2*t*(cx + 25) + 3*tt*t**2*(cx - 20) + t**3*(cx - 5)
        by = tt**3 * trunk_bot + 3*tt**2*t*(trunk_bot - 100) + 3*tt*t**2*(trunk_bot - 200) + t**3*trunk_top
        ctx.move_to(bx - 11, by)
        ctx.line_to(bx + 11, by)
        set_color(ctx, BROWN_DARK, 0.3)
        ctx.stroke()

    top_x, top_y = cx - 5, trunk_top

    # ── Fronds ──
    frond_angles = [i * math.pi / 4 for i in range(8)]
    for angle in frond_angles:
        frond_len = random.uniform(85, 115)
        end_x = top_x + math.cos(angle) * frond_len
        end_y = top_y + math.sin(angle) * frond_len * 0.7 - 15
        # Droop control point
        ctrl_x = top_x + math.cos(angle) * frond_len * 0.55
        ctrl_y = top_y + math.sin(angle) * frond_len * 0.25 - 35

        # Draw filled leaf shape (wide teardrop along the curve)
        # Build a filled frond: outline left side, tip, right side
        perp_angle = angle + math.pi / 2
        leaf_width = 18  # max half-width of frond

        # Sample points along the cubic bezier
        points_left = []
        points_right = []
        n_pts = 12
        for j in range(n_pts + 1):
            t = j / n_pts
            tt = 1 - t
            # Bezier point on spine
            px = tt**3*top_x + 3*tt**2*t*ctrl_x + 3*tt*t**2*end_x + t**3*end_x
            py = tt**3*top_y + 3*tt**2*t*ctrl_y + 3*tt*t**2*(end_y - 15) + t**3*end_y
            # Width tapers: widest at ~30%, narrows to tip
            width = leaf_width * math.sin(t * math.pi) * (1 - t * 0.3)
            if t < 0.08:
                width *= t / 0.08  # narrow at base too
            ox = math.cos(perp_angle) * width
            oy = math.sin(perp_angle) * width * 0.5
            points_left.append((px - ox, py - oy))
            points_right.append((px + ox, py + oy))

        # Draw filled frond shape
        ctx.move_to(*points_left[0])
        for pt in points_left[1:]:
            ctx.line_to(*pt)
        for pt in reversed(points_right):
            ctx.line_to(*pt)
        ctx.close_path()

        # Gradient along frond length
        pat = cairo.LinearGradient(top_x, top_y, end_x, end_y)
        pat.add_color_stop_rgb(0, *LEAF_MED)
        pat.add_color_stop_rgb(0.5, *LEAF_LIGHT)
        pat.add_color_stop_rgb(1, *LEAF_MED)
        ctx.set_source(pat)
        ctx.fill()

        # Spine line (center vein)
        ctx.set_line_width(1.8)
        ctx.move_to(top_x, top_y)
        ctx.curve_to(ctrl_x, ctrl_y, end_x, end_y - 15, end_x, end_y)
        set_color(ctx, LEAF_DARK, 0.6)
        ctx.stroke()

        # Leaf vein lines (subtle)
        ctx.set_line_width(0.7)
        for j in range(2, n_pts - 1):
            t = j / n_pts
            tt = 1 - t
            px = tt**3*top_x + 3*tt**2*t*ctrl_x + 3*tt*t**2*end_x + t**3*end_x
            py = tt**3*top_y + 3*tt**2*t*ctrl_y + 3*tt*t**2*(end_y - 15) + t**3*end_y
            width = leaf_width * math.sin(t * math.pi) * (1 - t * 0.3) * 0.8
            ox = math.cos(perp_angle) * width
            oy = math.sin(perp_angle) * width * 0.5
            for side in [-1, 1]:
                ctx.move_to(px, py)
                ctx.line_to(px + side * ox, py + side * oy)
                set_color(ctx, LEAF_DARK, 0.2)
                ctx.stroke()

    # Coconuts (gold accent)
    for dx, dy in [(-8, 8), (5, 10), (0, 15)]:
        draw_circle(ctx, top_x + dx, top_y + dy, 6, GOLD_PRIMARY)
        draw_circle(ctx, top_x + dx - 1, top_y + dy - 1, 2, GOLD_BRIGHT, 0.5)

    save_surface(surface, "tree_palm_front.png")


def generate_cactus(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    body_bot = cy_base - 25
    body_top = cy_base - 310
    body_w = 45

    # ── Main body (rounded rectangle / tall ellipse) ── (dark blue)
    pat = cairo.LinearGradient(cx - body_w, body_top, cx + body_w, body_bot)
    pat.add_color_stop_rgb(0, *LEAF_MED)
    pat.add_color_stop_rgb(0.5, *LEAF_DARK)
    pat.add_color_stop_rgb(1, *LEAF_SHADOW)

    # Rounded top, straight sides, flat bottom
    ctx.move_to(cx - body_w, body_bot)
    ctx.line_to(cx - body_w, body_top + body_w)
    ctx.arc(cx, body_top + body_w, body_w, math.pi, 0)
    ctx.line_to(cx + body_w, body_bot)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Ridges (vertical lines)
    ctx.set_line_width(1.2)
    for i in range(-3, 4):
        rx = cx + i * (body_w / 4)
        ctx.move_to(rx, body_top + body_w + 5)
        ctx.line_to(rx, body_bot - 5)
        set_color(ctx, LEAF_SHADOW, 0.35)
        ctx.stroke()

    # ── Left arm ──
    arm_y = body_bot - 160
    ctx.set_line_width(28)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.move_to(cx - body_w + 5, arm_y)
    ctx.curve_to(cx - body_w - 40, arm_y,
                 cx - body_w - 45, arm_y - 60,
                 cx - body_w - 40, arm_y - 80)
    set_color(ctx, LEAF_DARK)
    ctx.stroke()
    # Highlight
    ctx.set_line_width(8)
    ctx.move_to(cx - body_w + 2, arm_y)
    ctx.curve_to(cx - body_w - 38, arm_y,
                 cx - body_w - 43, arm_y - 55,
                 cx - body_w - 38, arm_y - 75)
    set_color(ctx, LEAF_MED, 0.4)
    ctx.stroke()

    # ── Right arm ──
    arm_y2 = body_bot - 120
    ctx.set_line_width(24)
    ctx.move_to(cx + body_w - 5, arm_y2)
    ctx.curve_to(cx + body_w + 35, arm_y2,
                 cx + body_w + 40, arm_y2 - 50,
                 cx + body_w + 35, arm_y2 - 70)
    set_color(ctx, LEAF_DARK)
    ctx.stroke()
    ctx.set_line_width(7)
    ctx.move_to(cx + body_w - 3, arm_y2)
    ctx.curve_to(cx + body_w + 33, arm_y2,
                 cx + body_w + 38, arm_y2 - 45,
                 cx + body_w + 33, arm_y2 - 65)
    set_color(ctx, LEAF_MED, 0.4)
    ctx.stroke()

    # Spine dots
    for _ in range(30):
        sx = cx + random.uniform(-body_w + 5, body_w - 5)
        sy = random.uniform(body_top + body_w + 10, body_bot - 10)
        draw_circle(ctx, sx, sy, 1.2, LEAF_BRIGHT, 0.6)

    # Flower on top (gold accent)
    flower_cx, flower_cy = cx, body_top + body_w - 8
    petals = 6
    for i in range(petals):
        angle = i * 2 * math.pi / petals
        px = flower_cx + math.cos(angle) * 10
        py = flower_cy + math.sin(angle) * 10
        draw_circle(ctx, px, py, 7, GOLD_BRIGHT, 0.85)
    draw_circle(ctx, flower_cx, flower_cy, 5, GOLD_PRIMARY)

    save_surface(surface, "tree_cactus_front.png")


def generate_swamp(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Twisted trunk ──
    trunk_bot = cy_base - 20
    trunk_top = cy_base - 280

    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, *BARK_SHADOW)
    pat.add_color_stop_rgb(1, 0.02, 0.03, 0.12)

    # Wide twisted trunk
    ctx.move_to(cx - 25, trunk_bot)
    ctx.curve_to(cx - 30, trunk_bot - 80, cx + 20, trunk_bot - 150, cx - 10, trunk_top)
    ctx.line_to(cx + 15, trunk_top + 10)
    ctx.curve_to(cx + 30, trunk_bot - 140, cx - 15, trunk_bot - 70, cx + 25, trunk_bot)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Visible roots
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    for side in [-1, 1]:
        for j in range(2):
            ctx.set_line_width(random.uniform(5, 9))
            rx = cx + side * (15 + j * 12)
            ctx.move_to(rx, trunk_bot)
            ctx.curve_to(rx + side * 20, trunk_bot + 8,
                         rx + side * 35, trunk_bot + 5,
                         rx + side * 45, trunk_bot + random.uniform(-5, 5))
            set_color(ctx, BARK_SHADOW)
            ctx.stroke()

    # ── Sparse droopy canopy ──
    canopy_cy = trunk_top + 10
    blobs = [
        (cx - 5, canopy_cy, 45),
        (cx - 45, canopy_cy + 20, 35),
        (cx + 40, canopy_cy + 15, 38),
        (cx, canopy_cy - 30, 35),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br,
                           LEAF_DARK, LEAF_SHADOW, 0.85, 0.7)

    # Hanging moss (GREEN tinted)
    ctx.set_line_width(1.2)
    for bx, by, br in blobs:
        for _ in range(random.randint(4, 8)):
            mx = bx + random.uniform(-br * 0.7, br * 0.7)
            my = by + br * 0.5
            moss_len = random.uniform(20, 50)
            ctx.move_to(mx, my)
            ctx.line_to(mx + random.uniform(-5, 5), my + moss_len)
            c = random.choice([GREEN_DARK, GREEN_MED, GRAY_MED])
            set_color(ctx, c, random.uniform(0.4, 0.7))
            ctx.stroke()

    # Green moss patches on trunk
    for _ in range(6):
        mx = cx + random.uniform(-20, 20)
        my = random.uniform(trunk_top + 30, trunk_bot - 20)
        mr = random.uniform(5, 12)
        draw_circle(ctx, mx, my, mr, GREEN_DARK, random.uniform(0.3, 0.5))

    save_surface(surface, "tree_swamp_front.png")


def generate_frost_pine(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Ice-blue trunk ──
    trunk_w, trunk_h = 20, 170
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 15
    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, *GRAY_LIGHT)
    pat.add_color_stop_rgb(1, *GRAY_MED)
    ctx.rectangle(trunk_x, trunk_y, trunk_w, trunk_h)
    ctx.set_source(pat)
    ctx.fill()

    # ── Snow-heavy pine triangles ──
    layers = [
        (cy_base - 160, 95, 65),
        (cy_base - 215, 78, 65),
        (cy_base - 265, 62, 60),
        (cy_base - 310, 46, 55),
        (cy_base - 350, 30, 50),
    ]
    for i, (ly, lw, lh) in enumerate(layers):
        # Main triangle (blue)
        pat = cairo.LinearGradient(cx, ly - lh, cx, ly)
        pat.add_color_stop_rgb(0, *LEAF_LIGHT)
        pat.add_color_stop_rgb(1, *LEAF_DARK)
        ctx.move_to(cx, ly - lh)
        ctx.line_to(cx + lw, ly)
        ctx.line_to(cx - lw, ly)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()

        # Heavy snow cap (white)
        snow_h = lh * 0.45
        snow_w = lw * 0.75
        ctx.move_to(cx, ly - lh)
        ctx.line_to(cx + snow_w, ly - lh + snow_h)
        # Lumpy snow bottom edge
        ctx.curve_to(cx + snow_w * 0.5, ly - lh + snow_h + 8,
                     cx - snow_w * 0.5, ly - lh + snow_h + 5,
                     cx - snow_w, ly - lh + snow_h)
        ctx.close_path()
        set_color(ctx, SNOW, 0.9)
        ctx.fill()

        # Icicles hanging from snow edge
        num_icicles = random.randint(3, 6)
        for j in range(num_icicles):
            t = (j + 0.5) / num_icicles
            ix = cx - snow_w + t * 2 * snow_w
            iy = ly - lh + snow_h + random.uniform(3, 8)
            icicle_len = random.uniform(8, 18)
            ctx.move_to(ix - 2, iy)
            ctx.line_to(ix, iy + icicle_len)
            ctx.line_to(ix + 2, iy)
            ctx.close_path()
            set_color(ctx, (0.80, 0.90, 1.0), 0.7)
            ctx.fill()

    save_surface(surface, "tree_frost_pine_front.png")


def generate_crystal_tree(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Crystal trunk ──
    trunk_bot = cy_base - 25
    trunk_top = cy_base - 250
    trunk_w = 16

    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, *LEAF_BRIGHT)
    pat.add_color_stop_rgb(0.5, *LEAF_LIGHT)
    pat.add_color_stop_rgb(1, *LEAF_MED)
    ctx.move_to(cx - trunk_w * 0.7, trunk_top)
    ctx.line_to(cx + trunk_w * 0.7, trunk_top)
    ctx.line_to(cx + trunk_w, trunk_bot)
    ctx.line_to(cx - trunk_w, trunk_bot)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # ── Crystal canopy: geometric angular shapes ──
    crystals = [
        # (tip_x, tip_y, base_y, half_width)
        (cx, trunk_top - 120, trunk_top + 20, 50),
        (cx - 40, trunk_top - 70, trunk_top + 30, 35),
        (cx + 40, trunk_top - 80, trunk_top + 25, 38),
        (cx - 20, trunk_top - 100, trunk_top + 10, 30),
        (cx + 25, trunk_top - 110, trunk_top + 5, 32),
        (cx, trunk_top - 60, trunk_top + 35, 45),
    ]

    for tip_x, tip_y, base_y, hw in crystals:
        # Blue crystal gradient
        pat = cairo.LinearGradient(tip_x - hw, tip_y, tip_x + hw, base_y)
        pat.add_color_stop_rgba(0, *LEAF_BRIGHT, 0.85)
        pat.add_color_stop_rgba(0.4, *LEAF_LIGHT, 0.80)
        pat.add_color_stop_rgba(0.7, *LEAF_MED, 0.75)
        pat.add_color_stop_rgba(1, *LEAF_BRIGHT, 0.70)

        # Diamond / angular shape
        mid_y = (tip_y + base_y) / 2
        ctx.move_to(tip_x, tip_y)
        ctx.line_to(tip_x + hw, mid_y)
        ctx.line_to(tip_x + hw * 0.6, base_y)
        ctx.line_to(tip_x - hw * 0.6, base_y)
        ctx.line_to(tip_x - hw, mid_y)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()

        # Edge highlights
        ctx.set_line_width(1.5)
        ctx.move_to(tip_x, tip_y)
        ctx.line_to(tip_x - hw, mid_y)
        set_color(ctx, WHITE, 0.5)
        ctx.stroke()

    # Pink magical sparkle highlights on crystals
    for _ in range(15):
        sx = cx + random.gauss(0, 40)
        sy = trunk_top - 50 + random.gauss(0, 50)
        sr = random.uniform(1.5, 4)
        c = random.choice([PINK_BRIGHT, PINK_MED, WHITE])
        draw_circle(ctx, sx, sy, sr, c, random.uniform(0.6, 1.0))

    save_surface(surface, "tree_crystal_tree_front.png")


def generate_ember_tree(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    trunk_bot = cy_base - 20
    trunk_top = cy_base - 280

    # ── Charred trunk (near-black blue) ──
    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, *BARK_SHADOW)
    pat.add_color_stop_rgb(1, 0.02, 0.03, 0.12)

    trunk_w = 28
    ctx.move_to(cx - trunk_w + 5, trunk_top)
    ctx.line_to(cx + trunk_w - 5, trunk_top)
    ctx.line_to(cx + trunk_w, trunk_bot)
    ctx.line_to(cx - trunk_w, trunk_bot)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Glowing cracks in trunk
    ctx.set_line_width(2)
    for _ in range(10):
        cy = random.uniform(trunk_top + 20, trunk_bot - 20)
        cxx = cx + random.uniform(-trunk_w + 5, trunk_w - 5)
        ctx.move_to(cxx, cy)
        ctx.curve_to(cxx + random.uniform(-8, 8), cy + 10,
                     cxx + random.uniform(-8, 8), cy + 20,
                     cxx + random.uniform(-10, 10), cy + random.uniform(15, 35))
        set_color(ctx, GOLD_PRIMARY, random.uniform(0.5, 0.9))
        ctx.stroke()
    # Glow around cracks (gold)
    ctx.set_line_width(6)
    for _ in range(5):
        cy = random.uniform(trunk_top + 30, trunk_bot - 30)
        cxx = cx + random.uniform(-trunk_w + 8, trunk_w - 8)
        ctx.move_to(cxx, cy)
        ctx.line_to(cxx + random.uniform(-5, 5), cy + random.uniform(10, 25))
        set_color(ctx, GOLD_DARK, 0.15)
        ctx.stroke()

    # ── Flame-colored canopy (YELLOW + PINK fire) ──
    canopy_cy = trunk_top + 10
    blobs = [
        (cx, canopy_cy - 30, 58),
        (cx - 42, canopy_cy, 42),
        (cx + 42, canopy_cy, 42),
        (cx - 20, canopy_cy - 55, 38),
        (cx + 20, canopy_cy - 55, 38),
        (cx, canopy_cy - 75, 35),
    ]
    # Glow behind (warm yellow-pink blend)
    glow = cairo.RadialGradient(cx, canopy_cy - 30, 20, cx, canopy_cy - 30, 100)
    glow.add_color_stop_rgba(0, *YELLOW_BRIGHT, 0.3)
    glow.add_color_stop_rgba(0.5, *PINK_BRIGHT, 0.15)
    glow.add_color_stop_rgba(1, *YELLOW_DARK, 0.0)
    ctx.arc(cx, canopy_cy - 30, 110, 0, 2 * math.pi)
    ctx.set_source(glow)
    ctx.fill()

    for i, (bx, by, br) in enumerate(blobs):
        # Alternate yellow and pink blobs for fiery look
        if i % 2 == 0:
            draw_radial_circle(ctx, bx, by, br, YELLOW_BRIGHT, YELLOW_DARK)
        else:
            draw_radial_circle(ctx, bx, by, br, PINK_BRIGHT, PINK_DARK)
    # Bright inner
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx, by - 5, br * 0.4,
                           GOLD_METAL, YELLOW_BRIGHT, 0.6, 0.0)

    # Ember particles (mix of yellow and pink)
    for _ in range(20):
        ex = cx + random.gauss(0, 55)
        ey = canopy_cy + random.gauss(-30, 50)
        er = random.uniform(1.5, 3.5)
        c = random.choice([YELLOW_BRIGHT, YELLOW_MED, PINK_BRIGHT, PINK_MED])
        draw_circle(ctx, ex, ey, er, c, random.uniform(0.6, 1.0))

    save_surface(surface, "tree_ember_tree_front.png")


def generate_dark_oak(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Very thick dark trunk (near-black blue) ──
    trunk_w, trunk_h = 55, 210
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 20
    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, *BARK_SHADOW)
    pat.add_color_stop_rgb(1, 0.02, 0.03, 0.12)
    taper = trunk_w * 0.08
    ctx.move_to(trunk_x + taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w - taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w + 5, trunk_y + trunk_h)
    ctx.line_to(trunk_x - 5, trunk_y + trunk_h)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    draw_bark_texture(ctx, trunk_x, trunk_y, trunk_w, trunk_h, (0.01, 0.02, 0.08), 20)
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, (0.01, 0.02, 0.08), 8)

    # Lichen patches (dark blue)
    for _ in range(5):
        mx = trunk_x + random.uniform(5, trunk_w - 5)
        my = trunk_y + random.uniform(20, trunk_h - 20)
        mr = random.uniform(6, 12)
        draw_circle(ctx, mx, my, mr, LEAF_SHADOW, 0.5)

    # Root buttresses
    for side in [-1, 1]:
        ctx.move_to(cx + side * (trunk_w / 2 + 3), cy_base - 20)
        ctx.curve_to(cx + side * (trunk_w / 2 + 30), cy_base - 8,
                     cx + side * (trunk_w / 2 + 40), cy_base,
                     cx + side * (trunk_w / 2 + 25), cy_base + 5)
        ctx.line_to(cx + side * trunk_w / 2, cy_base - 20)
        ctx.close_path()
        set_color(ctx, BARK_SHADOW)
        ctx.fill()

    # ── Dense dark canopy ──
    canopy_cy = trunk_y - 15
    blobs = [
        (cx, canopy_cy, 78),
        (cx - 60, canopy_cy + 18, 55),
        (cx + 60, canopy_cy + 18, 55),
        (cx - 35, canopy_cy - 42, 52),
        (cx + 35, canopy_cy - 42, 52),
        (cx, canopy_cy - 65, 48),
        (cx - 20, canopy_cy + 35, 50),
        (cx + 20, canopy_cy + 35, 50),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_SHADOW, (0.02, 0.04, 0.15))
    # Extra dark overlay
    for bx, by, br in blobs:
        draw_circle(ctx, bx + 3, by + 3, br * 0.6, (0.01, 0.02, 0.08), 0.3)

    # Tiny glowing eyes (creepy)
    eye_positions = [
        (cx - 30, canopy_cy + 5),
        (cx + 45, canopy_cy - 10),
        (cx - 10, canopy_cy - 35),
    ]
    for ex, ey in eye_positions:
        for dx in [-4, 4]:
            # Glow (gold)
            draw_circle(ctx, ex + dx, ey, 4, GOLD_PRIMARY, 0.15)
            # Eye (gold)
            draw_circle(ctx, ex + dx, ey, 2, GOLD_PRIMARY, 0.8)
            draw_circle(ctx, ex + dx, ey, 0.8, GOLD_BRIGHT, 1.0)

    save_surface(surface, "tree_dark_oak_front.png")


# ── Non-tree environment ────────────────────────────────────────────────────

def generate_bush(w=128, h=128):
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.6

    # Dark blue stems
    ctx.set_line_width(3)
    for angle in [-0.5, -0.2, 0.1, 0.4]:
        ctx.move_to(cx + angle * 15, h - 10)
        ctx.line_to(cx + angle * 25, cy + 5)
        set_color(ctx, BARK_SHADOW)
        ctx.stroke()

    # Blue leaf clusters
    blobs = [
        (cx, cy, 30),
        (cx - 28, cy + 8, 22),
        (cx + 28, cy + 8, 22),
        (cx - 15, cy - 15, 20),
        (cx + 15, cy - 15, 20),
        (cx, cy + 15, 25),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_MED, LEAF_DARK)

    # Highlight
    for bx, by, br in blobs[:2]:
        draw_radial_circle(ctx, bx - 3, by - 3, br * 0.4,
                           LEAF_LIGHT, LEAF_MED, 0.5, 0.0)

    # Green berry accents
    for _ in range(6):
        fx = cx + random.uniform(-30, 30)
        fy = cy + random.uniform(-15, 15)
        c = random.choice([GREEN_BRIGHT, GREEN_MED])
        draw_circle(ctx, fx, fy, random.uniform(2, 3.5), c, 0.85)

    save_surface(surface, "bush.png")


def generate_rock(w=96, h=96):
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.55

    # Main boulder shape - irregular rounded
    rx, ry = 38, 28
    pat = cairo.RadialGradient(cx - 10, cy - 10, 5, cx, cy, 40)
    pat.add_color_stop_rgb(0, *GRAY_LIGHT)
    pat.add_color_stop_rgb(0.6, *GRAY_MED)
    pat.add_color_stop_rgb(1, *GRAY_DARK)

    # Draw irregular boulder with curves
    ctx.move_to(cx - rx, cy + 5)
    ctx.curve_to(cx - rx - 3, cy - ry * 0.5, cx - rx * 0.4, cy - ry, cx, cy - ry + 2)
    ctx.curve_to(cx + rx * 0.5, cy - ry - 3, cx + rx + 2, cy - ry * 0.4, cx + rx, cy + 3)
    ctx.curve_to(cx + rx + 1, cy + ry * 0.6, cx + rx * 0.3, cy + ry, cx - 5, cy + ry - 2)
    ctx.curve_to(cx - rx * 0.5, cy + ry + 1, cx - rx - 2, cy + ry * 0.3, cx - rx, cy + 5)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Crack lines
    ctx.set_line_width(1.0)
    cracks = [
        (cx - 10, cy - 10, cx + 5, cy + 5),
        (cx + 8, cy - 5, cx + 15, cy + 8),
    ]
    for x0, y0, x1, y1 in cracks:
        ctx.move_to(x0, y0)
        ctx.curve_to(x0 + 3, y0 + 5, x1 - 3, y1 - 3, x1, y1)
        set_color(ctx, GRAY_DARK, 0.5)
        ctx.stroke()

    # Highlight on upper-left
    ctx.arc(cx - 12, cy - 12, 12, 0, 2 * math.pi)
    set_color(ctx, WHITE, 0.15)
    ctx.fill()

    # Green moss patch
    draw_circle(ctx, cx - 15, cy + 8, 8, GREEN_DARK, 0.35)
    draw_circle(ctx, cx - 12, cy + 5, 5, GREEN_MED, 0.25)

    # Pink crystal fleck
    draw_circle(ctx, cx + 15, cy - 5, 4, PINK_DARK, 0.4)
    draw_circle(ctx, cx + 16, cy - 6, 2, PINK_MED, 0.3)

    save_surface(surface, "rock.png")


def generate_grass(w=64, h=128):
    """Mycelium network — branching blue tendrils with gold spark nodes.
    Looks like a neural network / brain pathways from afar, spaghetti grass up close."""
    surface, ctx = make_surface(w, h)
    random.seed(777)  # Deterministic mycelium

    # Build a network of nodes and connections
    nodes = []
    for _ in range(25):
        nodes.append((random.uniform(4, w - 4), random.uniform(10, h - 10)))

    # Add root nodes at the bottom
    for x in range(5, w, 8):
        nodes.append((x + random.uniform(-2, 2), h - random.uniform(3, 12)))

    # Draw tendril connections — branching paths between nearby nodes
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    for i, (x1, y1) in enumerate(nodes):
        # Connect to 2-3 nearest neighbors
        dists = []
        for j, (x2, y2) in enumerate(nodes):
            if i == j:
                continue
            d = math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
            if d < 35:  # Only connect nearby nodes
                dists.append((d, j, x2, y2))
        dists.sort()

        for k, (d, j, x2, y2) in enumerate(dists[:3]):
            # Tendril thickness based on depth (thicker near bottom)
            avg_y = (y1 + y2) / 2
            thickness = 0.8 + (avg_y / h) * 1.5

            # Curved path with random wobble
            mid_x = (x1 + x2) / 2 + random.uniform(-8, 8)
            mid_y = (y1 + y2) / 2 + random.uniform(-5, 5)

            # Blue tendril with slight brightness variation
            brightness = 0.6 + random.uniform(0, 0.3)
            ctx.set_line_width(thickness)
            ctx.move_to(x1, y1)
            ctx.curve_to(mid_x - 3, mid_y, mid_x + 3, mid_y, x2, y2)
            set_color(ctx, (LEAF_DARK[0] * brightness,
                           LEAF_DARK[1] * brightness,
                           LEAF_DARK[2] * brightness), 0.7)
            ctx.stroke()

            # Thinner bright highlight tendril on top
            ctx.set_line_width(thickness * 0.4)
            ctx.move_to(x1, y1)
            ctx.curve_to(mid_x - 3, mid_y, mid_x + 3, mid_y, x2, y2)
            set_color(ctx, LEAF_MED, 0.3)
            ctx.stroke()

    # Draw spark nodes at junctions (alternating YELLOW, PINK, GREEN)
    spark_colors = [YELLOW_MED, PINK_MED, GREEN_MED]
    spark_brights = [YELLOW_BRIGHT, PINK_BRIGHT, GREEN_BRIGHT]
    for idx, (x, y) in enumerate(nodes):
        # Small blue node
        draw_circle(ctx, x, y, random.uniform(1.2, 2.5), LEAF_MED, 0.6)

        # Colored spark on ~40% of nodes
        if random.random() < 0.4:
            spark_r = random.uniform(1.0, 2.0)
            c_idx = idx % 3
            draw_circle(ctx, x, y, spark_r, spark_colors[c_idx], 0.8)
            # Bright center
            draw_circle(ctx, x, y, spark_r * 0.4, spark_brights[c_idx], 0.9)

    # Traveling sparks along some tendrils (PINK primary)
    for _ in range(12):
        i = random.randint(0, len(nodes) - 1)
        x1, y1 = nodes[i]
        # Find a connected node
        nearest = None
        best_d = 999
        for j, (x2, y2) in enumerate(nodes):
            if i == j:
                continue
            d = math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
            if d < 30 and d < best_d:
                best_d = d
                nearest = (x2, y2)
        if nearest:
            x2, y2 = nearest
            t = random.uniform(0.2, 0.8)
            sx = x1 + (x2 - x1) * t
            sy = y1 + (y2 - y1) * t
            c = random.choice([PINK_MED, PINK_BRIGHT])
            draw_circle(ctx, sx, sy, random.uniform(0.8, 1.5), c, 0.9)
            # Glow halo
            draw_circle(ctx, sx, sy, random.uniform(2.5, 4.0), PINK_BRIGHT, 0.15)

    random.seed(42)  # Reset seed
    save_surface(surface, "grass.png")


# ── New tree generators ─────────────────────────────────────────────────────

def generate_willow(w=256, h=512):
    """Weeping willow — thin trunk, cascading curtain of hanging leaf lines."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Thin trunk ──
    trunk_w, trunk_h = 20, 220
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 15
    draw_trunk_gradient(ctx, trunk_x, trunk_y, trunk_w, trunk_h,
                        BARK_MED, BARK_DARK)
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, BARK_SHADOW, 5)

    # Small root spread
    for side in [-1, 1]:
        ctx.move_to(cx + side * trunk_w / 2, cy_base - 15)
        ctx.curve_to(cx + side * (trunk_w / 2 + 12), cy_base - 5,
                     cx + side * (trunk_w / 2 + 15), cy_base,
                     cx + side * (trunk_w / 2 + 8), cy_base + 3)
        ctx.line_to(cx + side * trunk_w / 2, cy_base - 15)
        ctx.close_path()
        set_color(ctx, BARK_DARK)
        ctx.fill()

    # ── Branch structure (short, spreading outward) ──
    branch_y = trunk_y + 20
    branches = []
    for i in range(7):
        angle = -math.pi * 0.15 + i * math.pi * 0.22 / 6 * 2 - math.pi * 0.07
        blen = random.uniform(50, 90)
        bx = cx + math.cos(angle - math.pi / 2) * blen
        by = branch_y + math.sin(angle - math.pi / 2) * blen * 0.3 + random.uniform(-10, 20)
        branches.append((bx, by))
        ctx.set_line_width(random.uniform(3, 6))
        ctx.move_to(cx, branch_y + 10)
        ctx.curve_to(cx + (bx - cx) * 0.4, branch_y,
                     cx + (bx - cx) * 0.7, by + 10,
                     bx, by)
        set_color(ctx, BARK_MED)
        ctx.stroke()

    # ── Cascading leaf curtains ──
    ctx.set_line_width(1.2)
    for bx, by in branches:
        num_strands = random.randint(8, 14)
        for _ in range(num_strands):
            sx = bx + random.uniform(-20, 20)
            sy = by + random.uniform(-5, 5)
            strand_len = random.uniform(100, 250)
            sway = random.uniform(-15, 15)

            # Draw strand as curved line
            ctx.move_to(sx, sy)
            ctx.curve_to(sx + sway * 0.3, sy + strand_len * 0.3,
                         sx + sway * 0.7, sy + strand_len * 0.6,
                         sx + sway, sy + strand_len)
            c = random.choice([LEAF_LIGHT, LEAF_MED, LEAF_DARK])
            set_color(ctx, c, random.uniform(0.5, 0.85))
            ctx.stroke()

            # Small leaf dots along strand
            for j in range(random.randint(3, 7)):
                t = random.uniform(0.1, 0.95)
                lx = sx + sway * t + random.uniform(-3, 3)
                ly = sy + strand_len * t + random.uniform(-3, 3)
                lr = random.uniform(2, 4)
                draw_circle(ctx, lx, ly, lr, random.choice([LEAF_BRIGHT, LEAF_LIGHT, LEAF_MED]),
                           random.uniform(0.4, 0.7))

    # Canopy mass at top (behind strands gives depth)
    canopy_cy = branch_y - 10
    for bx_c, by_c, br in [(cx, canopy_cy, 40), (cx - 30, canopy_cy + 5, 30), (cx + 30, canopy_cy + 5, 30)]:
        draw_radial_circle(ctx, bx_c, by_c, br, LEAF_MED, LEAF_DARK, 0.6, 0.3)

    save_surface(surface, "tree_willow_front.png")


def generate_birch(w=256, h=512):
    """Birch tree — thin white-blue trunk with horizontal dark marks, small round canopy."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Thin white-blue trunk ──
    trunk_w, trunk_h = 16, 260
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 15

    # White-blue bark
    BIRCH_LIGHT = (0.70, 0.75, 0.90)
    BIRCH_MED = (0.55, 0.60, 0.78)

    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, *BIRCH_LIGHT)
    pat.add_color_stop_rgb(1, *BIRCH_MED)
    taper = trunk_w * 0.1
    ctx.move_to(trunk_x + taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w - taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w, trunk_y + trunk_h)
    ctx.line_to(trunk_x, trunk_y + trunk_h)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Horizontal dark marks (birch bark lenticels)
    ctx.set_line_width(1.5)
    for i in range(18):
        my = trunk_y + trunk_h * (i + 0.5) / 18 + random.uniform(-3, 3)
        mark_w = random.uniform(6, trunk_w - 2)
        mx = trunk_x + (trunk_w - mark_w) / 2 + random.uniform(-2, 2)
        ctx.move_to(mx, my)
        ctx.line_to(mx + mark_w, my + random.uniform(-1, 1))
        set_color(ctx, BARK_SHADOW, random.uniform(0.3, 0.6))
        ctx.stroke()

    # ── Small round canopy ──
    canopy_cy = trunk_y - 10
    blobs = [
        (cx, canopy_cy, 48),
        (cx - 30, canopy_cy + 10, 35),
        (cx + 30, canopy_cy + 10, 35),
        (cx - 15, canopy_cy - 25, 32),
        (cx + 15, canopy_cy - 25, 32),
        (cx, canopy_cy - 40, 28),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_LIGHT, LEAF_MED)
    for bx, by, br in blobs[:2]:
        draw_radial_circle(ctx, bx - 5, by - 5, br * 0.4,
                           LEAF_BRIGHT, LEAF_LIGHT, 0.5, 0.0)

    # Leaf detail dots
    for _ in range(25):
        dx = cx + random.gauss(0, 30)
        dy = canopy_cy + random.gauss(0, 25)
        dr = random.uniform(2, 5)
        c = random.choice([LEAF_BRIGHT, LEAF_LIGHT])
        draw_circle(ctx, dx, dy, dr, c, random.uniform(0.3, 0.5))

    save_surface(surface, "tree_birch_front.png")


def generate_baobab(w=256, h=512):
    """Baobab — massive thick trunk taking up half the width, small flat canopy on top."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Massive trunk ──
    trunk_w = 110  # Very wide
    trunk_h = 280
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 15

    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, *BARK_MED)
    pat.add_color_stop_rgb(0.5, *BARK_DARK)
    pat.add_color_stop_rgb(1, *BARK_SHADOW)

    # Bulbous shape — wider in middle, tapers at top
    ctx.move_to(cx - trunk_w * 0.35, trunk_y)
    ctx.curve_to(cx - trunk_w * 0.6, trunk_y + trunk_h * 0.3,
                 cx - trunk_w * 0.55, trunk_y + trunk_h * 0.7,
                 cx - trunk_w * 0.45, trunk_y + trunk_h)
    ctx.line_to(cx + trunk_w * 0.45, trunk_y + trunk_h)
    ctx.curve_to(cx + trunk_w * 0.55, trunk_y + trunk_h * 0.7,
                 cx + trunk_w * 0.6, trunk_y + trunk_h * 0.3,
                 cx + trunk_w * 0.35, trunk_y)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Bark texture — lots of vertical cracks
    draw_bark_texture(ctx, trunk_x + 15, trunk_y + 10, trunk_w - 30, trunk_h - 20, BARK_SHADOW, 30)
    # Vertical wrinkle lines
    ctx.set_line_width(1.0)
    for i in range(8):
        lx = cx + random.uniform(-trunk_w * 0.35, trunk_w * 0.35)
        ctx.move_to(lx, trunk_y + 20)
        ctx.curve_to(lx + random.uniform(-5, 5), trunk_y + trunk_h * 0.3,
                     lx + random.uniform(-5, 5), trunk_y + trunk_h * 0.7,
                     lx + random.uniform(-3, 3), trunk_y + trunk_h - 10)
        set_color(ctx, BARK_SHADOW, 0.4)
        ctx.stroke()

    # Root flares
    for side in [-1, 1]:
        for j in range(2):
            ctx.set_line_width(random.uniform(6, 10))
            rx = cx + side * (trunk_w * 0.4 + j * 10)
            ctx.move_to(rx, cy_base - 15)
            ctx.curve_to(rx + side * 20, cy_base - 3,
                         rx + side * 30, cy_base + 2,
                         rx + side * 35, cy_base + 5)
            set_color(ctx, BARK_SHADOW)
            ctx.stroke()

    # ── Small flat canopy on top ──
    canopy_cy = trunk_y - 5
    # Short stubby branches spreading out
    for angle_off in [-0.6, -0.3, 0, 0.3, 0.6]:
        bx = cx + math.sin(angle_off) * 60
        by = canopy_cy - 10 + abs(angle_off) * 10
        ctx.set_line_width(random.uniform(4, 8))
        ctx.move_to(cx + angle_off * 15, trunk_y + 10)
        ctx.curve_to(cx + angle_off * 30, canopy_cy,
                     bx * 0.7 + cx * 0.3, by + 5,
                     bx, by)
        set_color(ctx, BARK_MED)
        ctx.stroke()

    # Flat wide canopy blobs
    blobs = [
        (cx, canopy_cy - 20, 50),
        (cx - 50, canopy_cy - 10, 35),
        (cx + 50, canopy_cy - 10, 35),
        (cx - 25, canopy_cy - 30, 30),
        (cx + 25, canopy_cy - 30, 30),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_MED, LEAF_DARK, 0.8, 0.6)

    save_surface(surface, "tree_baobab_front.png")


def generate_cherry_blossom(w=256, h=512):
    """Cherry blossom — medium trunk, pink-blue canopy with scattered petal dots."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # Pink-blue colors (warm blue-pink blend, still in blue family)
    CHERRY_LIGHT = (0.65, 0.50, 0.85)   # Light lavender-blue-pink
    CHERRY_MED   = (0.50, 0.35, 0.75)   # Medium purple-blue
    CHERRY_DARK  = (0.30, 0.20, 0.55)   # Dark purple-blue
    CHERRY_PETAL = (0.70, 0.55, 0.90)   # Bright petal

    # ── Medium trunk ──
    trunk_w, trunk_h = 28, 200
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 18
    draw_trunk_gradient(ctx, trunk_x, trunk_y, trunk_w, trunk_h,
                        BARK_MED, BARK_DARK)
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, BARK_SHADOW, 5)

    # Branches splitting near top
    for angle in [-0.5, -0.15, 0.2, 0.5]:
        blen = random.uniform(30, 60)
        bx = cx + math.sin(angle) * blen
        by = trunk_y + 20 + abs(angle) * 15
        ctx.set_line_width(random.uniform(3, 6))
        ctx.move_to(cx, trunk_y + 30)
        ctx.curve_to(cx + (bx - cx) * 0.4, trunk_y + 10,
                     bx * 0.7 + cx * 0.3, by + 5,
                     bx, by)
        set_color(ctx, BARK_MED)
        ctx.stroke()

    # ── Canopy — purple-blue-pink clouds ──
    canopy_cy = trunk_y - 15
    blobs = [
        (cx, canopy_cy, 60),
        (cx - 50, canopy_cy + 12, 42),
        (cx + 50, canopy_cy + 12, 42),
        (cx - 28, canopy_cy - 35, 40),
        (cx + 28, canopy_cy - 35, 40),
        (cx, canopy_cy - 55, 35),
        (cx - 15, canopy_cy + 30, 38),
        (cx + 15, canopy_cy + 30, 38),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, CHERRY_LIGHT, CHERRY_DARK)
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx - 5, by - 5, br * 0.4,
                           CHERRY_PETAL, CHERRY_LIGHT, 0.5, 0.0)

    # Petal detail dots
    for _ in range(50):
        dx = cx + random.gauss(0, 50)
        dy = canopy_cy + random.gauss(0, 40)
        dr = random.uniform(2, 5)
        c = random.choice([CHERRY_PETAL, CHERRY_LIGHT, CHERRY_MED])
        draw_circle(ctx, dx, dy, dr, c, random.uniform(0.4, 0.7))

    # Falling petal dots below canopy
    for _ in range(15):
        px = cx + random.gauss(0, 60)
        py = canopy_cy + random.uniform(50, 180)
        pr = random.uniform(1.5, 3)
        draw_circle(ctx, px, py, pr, CHERRY_PETAL, random.uniform(0.2, 0.5))

    # Gold center accents (stamens visible)
    for _ in range(8):
        gx = cx + random.gauss(0, 35)
        gy = canopy_cy + random.gauss(0, 30)
        draw_circle(ctx, gx, gy, 1.5, GOLD_PRIMARY, 0.6)

    save_surface(surface, "tree_cherry_blossom_front.png")


def generate_mushroom_giant(w=256, h=512):
    """Giant mushroom tree — thick stem, massive dome cap with gold spots underneath."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Thick stem ──
    stem_w, stem_h = 40, 220
    stem_x = cx - stem_w / 2
    stem_y = cy_base - stem_h - 15

    STEM_LIGHT = (0.50, 0.55, 0.75)
    STEM_DARK  = (0.30, 0.35, 0.55)

    pat = cairo.LinearGradient(stem_x, stem_y, stem_x, stem_y + stem_h)
    pat.add_color_stop_rgb(0, *STEM_LIGHT)
    pat.add_color_stop_rgb(1, *STEM_DARK)
    # Slightly bulging stem
    ctx.move_to(cx - stem_w * 0.4, stem_y)
    ctx.curve_to(cx - stem_w * 0.55, stem_y + stem_h * 0.3,
                 cx - stem_w * 0.5, stem_y + stem_h * 0.7,
                 cx - stem_w * 0.45, stem_y + stem_h)
    ctx.line_to(cx + stem_w * 0.45, stem_y + stem_h)
    ctx.curve_to(cx + stem_w * 0.5, stem_y + stem_h * 0.7,
                 cx + stem_w * 0.55, stem_y + stem_h * 0.3,
                 cx + stem_w * 0.4, stem_y)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Stem texture — horizontal rings
    ctx.set_line_width(0.8)
    for i in range(12):
        ry = stem_y + stem_h * (i + 0.5) / 12
        ctx.move_to(cx - stem_w * 0.42, ry)
        ctx.line_to(cx + stem_w * 0.42, ry)
        set_color(ctx, STEM_DARK, 0.25)
        ctx.stroke()

    # ── Massive dome cap ──
    cap_cx = cx
    cap_cy = stem_y + 10
    cap_rx = 110  # Very wide
    cap_ry = 65   # Flatter dome

    # Cap shadow
    ctx.save()
    ctx.translate(cap_cx + 5, cap_cy + 5)
    ctx.scale(cap_rx, cap_ry)
    ctx.arc(0, 0, 1, math.pi, 0)
    ctx.restore()
    set_color(ctx, (0.02, 0.04, 0.12), 0.3)
    ctx.fill()

    # Main cap
    pat = cairo.RadialGradient(cap_cx - 20, cap_cy - cap_ry * 0.5, cap_ry * 0.1,
                               cap_cx, cap_cy, cap_rx)
    pat.add_color_stop_rgb(0, *LEAF_BRIGHT)
    pat.add_color_stop_rgb(0.5, *LEAF_MED)
    pat.add_color_stop_rgb(1, *LEAF_DARK)

    ctx.save()
    ctx.translate(cap_cx, cap_cy)
    ctx.scale(cap_rx, cap_ry)
    ctx.arc(0, 0, 1, math.pi, 0)
    ctx.restore()
    ctx.set_source(pat)
    ctx.fill()

    # Underside of cap (darker, with gold gills/spots)
    ctx.save()
    ctx.translate(cap_cx, cap_cy)
    ctx.scale(cap_rx * 0.95, cap_ry * 0.3)
    ctx.arc(0, 0, 1, 0, math.pi)
    ctx.restore()
    set_color(ctx, LEAF_SHADOW, 0.7)
    ctx.fill()

    # Gold spots on cap top
    for _ in range(12):
        sx = cap_cx + random.uniform(-cap_rx * 0.7, cap_rx * 0.7)
        # Keep spots on top half of dome
        max_sy = cap_cy - cap_ry * 0.1
        min_sy = cap_cy - cap_ry * 0.9
        sy = random.uniform(min_sy, max_sy)
        sr = random.uniform(4, 10)
        draw_circle(ctx, sx, sy, sr, GOLD_PRIMARY, random.uniform(0.5, 0.8))
        draw_circle(ctx, sx - 1, sy - 1, sr * 0.4, GOLD_BRIGHT, 0.4)

    # Gold gill dots underneath
    for _ in range(8):
        gx = cap_cx + random.uniform(-cap_rx * 0.6, cap_rx * 0.6)
        gy = cap_cy + random.uniform(2, cap_ry * 0.25)
        draw_circle(ctx, gx, gy, random.uniform(2, 4), GOLD_PRIMARY, 0.6)

    save_surface(surface, "tree_mushroom_giant_front.png")


# ── New small vegetation generators ────────────────────────────────────────

def generate_fern(w=128, h=128):
    """Curled fern fronds — 3-4 spiral fronds from center."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 10

    num_fronds = 4
    for i in range(num_fronds):
        angle_base = -math.pi * 0.35 + i * math.pi * 0.7 / (num_fronds - 1)
        frond_len = random.uniform(55, 80)
        curl_amount = random.uniform(0.8, 1.5)

        # Draw frond as series of connected segments with leaflets
        prev_x, prev_y = cx, cy_base
        ctx.set_line_width(2.5)
        segments = 15
        for j in range(segments):
            t = (j + 1) / segments
            # Spiral: angle increases along length
            angle = angle_base - t * curl_amount
            seg_x = cx + math.sin(angle_base) * frond_len * t + math.sin(angle) * frond_len * t * 0.3
            seg_y = cy_base - frond_len * t * 0.9 + math.cos(angle) * frond_len * t * 0.15

            # Main stem
            ctx.move_to(prev_x, prev_y)
            ctx.line_to(seg_x, seg_y)
            c = LEAF_MED if t < 0.5 else LEAF_DARK
            set_color(ctx, c, 0.8)
            ctx.stroke()

            # Leaflets on sides (smaller toward tip)
            if j > 1 and j < segments - 1:
                leaflet_len = (1 - t) * 15 + 3
                perp = angle_base + math.pi / 2
                for side in [-1, 1]:
                    lx = seg_x + math.cos(perp) * side * leaflet_len
                    ly = seg_y + math.sin(perp) * side * leaflet_len * 0.5
                    ctx.set_line_width(1.2)
                    ctx.move_to(seg_x, seg_y)
                    ctx.line_to(lx, ly)
                    set_color(ctx, random.choice([LEAF_LIGHT, LEAF_MED]), random.uniform(0.5, 0.8))
                    ctx.stroke()
                    # Tiny leaf blob
                    draw_circle(ctx, lx, ly, random.uniform(1.5, 3), LEAF_LIGHT, 0.5)

            prev_x, prev_y = seg_x, seg_y

        # Curled tip (fiddle head)
        tip_r = random.uniform(3, 6)
        draw_circle(ctx, prev_x, prev_y, tip_r, LEAF_BRIGHT, 0.7)

    save_surface(surface, "fern.png")


def generate_flower_blue(w=128, h=128):
    """Blue flower on a stem with gold center dot."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    # Stem
    stem_top_y = 40
    ctx.set_line_width(2.5)
    ctx.move_to(cx, cy_base)
    ctx.curve_to(cx - 3, cy_base - 25, cx + 3, stem_top_y + 20, cx, stem_top_y)
    set_color(ctx, LEAF_DARK, 0.9)
    ctx.stroke()

    # Small leaves on stem
    for ly in [cy_base - 25, cy_base - 50]:
        for side in [-1, 1]:
            ctx.move_to(cx, ly)
            ctx.curve_to(cx + side * 8, ly - 5,
                         cx + side * 12, ly - 3,
                         cx + side * 10, ly + 2)
            ctx.curve_to(cx + side * 6, ly + 3,
                         cx + side * 2, ly + 1,
                         cx, ly)
            ctx.close_path()
            set_color(ctx, LEAF_MED, 0.7)
            ctx.fill()

    # 5-petal flower
    flower_cx, flower_cy = cx, stem_top_y - 5
    petals = 5
    petal_r = 14
    for i in range(petals):
        angle = i * 2 * math.pi / petals - math.pi / 2
        px = flower_cx + math.cos(angle) * petal_r * 0.6
        py = flower_cy + math.sin(angle) * petal_r * 0.6
        draw_radial_circle(ctx, px, py, petal_r, LEAF_BRIGHT, LEAF_MED, 0.9, 0.7)

    # Gold center
    draw_circle(ctx, flower_cx, flower_cy, 5, GOLD_PRIMARY, 0.95)
    draw_circle(ctx, flower_cx - 1, flower_cy - 1, 2, GOLD_BRIGHT, 0.7)

    save_surface(surface, "flower_blue.png")


def generate_flower_gold(w=128, h=128):
    """Gold flower with blue center — accent plant."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    # Stem
    stem_top_y = 38
    ctx.set_line_width(2.5)
    ctx.move_to(cx, cy_base)
    ctx.curve_to(cx + 2, cy_base - 25, cx - 3, stem_top_y + 20, cx, stem_top_y)
    set_color(ctx, LEAF_DARK, 0.9)
    ctx.stroke()

    # Small leaves
    for ly in [cy_base - 30, cy_base - 55]:
        for side in [-1, 1]:
            ctx.move_to(cx, ly)
            ctx.curve_to(cx + side * 7, ly - 4,
                         cx + side * 11, ly - 2,
                         cx + side * 9, ly + 2)
            ctx.curve_to(cx + side * 5, ly + 3,
                         cx + side * 2, ly + 1,
                         cx, ly)
            ctx.close_path()
            set_color(ctx, LEAF_MED, 0.7)
            ctx.fill()

    # 5-petal gold flower
    flower_cx, flower_cy = cx, stem_top_y - 6
    petals = 5
    petal_r = 15
    for i in range(petals):
        angle = i * 2 * math.pi / petals - math.pi / 2
        px = flower_cx + math.cos(angle) * petal_r * 0.6
        py = flower_cy + math.sin(angle) * petal_r * 0.6
        draw_radial_circle(ctx, px, py, petal_r, GOLD_BRIGHT, GOLD_DARK, 0.9, 0.7)

    # Blue center
    draw_circle(ctx, flower_cx, flower_cy, 5, LEAF_BRIGHT, 0.95)
    draw_circle(ctx, flower_cx - 1, flower_cy - 1, 2, LEAF_LIGHT, 0.6)

    # Gold glow
    glow = cairo.RadialGradient(flower_cx, flower_cy, 5, flower_cx, flower_cy, 25)
    glow.add_color_stop_rgba(0, *GOLD_BRIGHT, 0.15)
    glow.add_color_stop_rgba(1, *GOLD_DARK, 0.0)
    ctx.arc(flower_cx, flower_cy, 25, 0, 2 * math.pi)
    ctx.set_source(glow)
    ctx.fill()

    save_surface(surface, "flower_gold.png")


def generate_tall_grass(w=128, h=128):
    """Taller, wispier grass blades — 128x128."""
    surface, ctx = make_surface(w, h)
    cx = w / 2

    blades = [
        (cx - 30, 0.95, -0.25),
        (cx - 20, 1.0, -0.1),
        (cx - 10, 1.05, 0.08),
        (cx, 1.0, -0.05),
        (cx + 10, 0.95, 0.15),
        (cx + 20, 0.9, 0.2),
        (cx + 30, 0.85, -0.12),
        (cx - 25, 0.8, 0.1),
        (cx + 5, 0.88, -0.18),
        (cx + 25, 0.78, 0.08),
    ]

    for bx, height_frac, lean in blades:
        blade_h = h * height_frac * 0.85
        base_y = h - 3
        tip_y = base_y - blade_h
        tip_x = bx + lean * 40

        blade_w = random.uniform(2, 4)

        pat = cairo.LinearGradient(bx, base_y, tip_x, tip_y)
        pat.add_color_stop_rgb(0, *LEAF_DARK)
        pat.add_color_stop_rgb(0.5, *LEAF_MED)
        pat.add_color_stop_rgb(1, *LEAF_BRIGHT)

        ctrl_x = bx + lean * 20
        ctrl_y = base_y - blade_h * 0.5

        ctx.move_to(bx - blade_w, base_y)
        ctx.curve_to(ctrl_x - blade_w * 0.4, ctrl_y,
                     tip_x - 0.5, tip_y + 8,
                     tip_x, tip_y)
        ctx.curve_to(tip_x + 0.5, tip_y + 8,
                     ctrl_x + blade_w * 0.4, ctrl_y,
                     bx + blade_w, base_y)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()

    # Seed heads on a few blades (gold accent)
    for _ in range(3):
        sx = cx + random.uniform(-25, 25)
        sy = random.uniform(5, 25)
        for j in range(4):
            draw_circle(ctx, sx + random.uniform(-2, 2), sy + j * 3,
                       1.2, GOLD_PRIMARY, 0.5)

    save_surface(surface, "tall_grass.png")


def generate_cattail(w=128, h=128):
    """Cattail — thin stem with brown-blue oval top."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 5

    CATTAIL_DARK  = (0.15, 0.12, 0.35)  # Dark brown-blue
    CATTAIL_LIGHT = (0.25, 0.20, 0.45)  # Lighter brown-blue

    # Two or three stems at slight offsets
    stems = [(cx - 10, 0.95), (cx + 5, 1.0), (cx + 18, 0.85)]
    for sx, height_mult in stems:
        stem_top = 15 * (1.0 / height_mult)

        # Thin stem
        ctx.set_line_width(2.0)
        ctx.move_to(sx, cy_base)
        ctx.line_to(sx + random.uniform(-2, 2), stem_top + 25)
        set_color(ctx, LEAF_DARK, 0.8)
        ctx.stroke()

        # Cattail head (oval)
        head_cx = sx + random.uniform(-1, 1)
        head_cy = stem_top + 18
        head_w = 6
        head_h = 18

        pat = cairo.LinearGradient(head_cx, head_cy - head_h, head_cx, head_cy + head_h)
        pat.add_color_stop_rgb(0, *CATTAIL_LIGHT)
        pat.add_color_stop_rgb(1, *CATTAIL_DARK)

        ctx.save()
        ctx.translate(head_cx, head_cy)
        ctx.scale(head_w, head_h)
        ctx.arc(0, 0, 1, 0, 2 * math.pi)
        ctx.restore()
        ctx.set_source(pat)
        ctx.fill()

        # Fuzzy texture on head
        for _ in range(8):
            fx = head_cx + random.uniform(-head_w * 0.6, head_w * 0.6)
            fy = head_cy + random.uniform(-head_h * 0.7, head_h * 0.7)
            draw_circle(ctx, fx, fy, 1, CATTAIL_LIGHT, 0.3)

        # Thin tip spike above head
        ctx.set_line_width(1.0)
        ctx.move_to(head_cx, head_cy - head_h)
        ctx.line_to(head_cx, head_cy - head_h - 12)
        set_color(ctx, LEAF_MED, 0.6)
        ctx.stroke()

    # Leaf blades (long, from base)
    for angle in [-0.3, 0.15, -0.1]:
        bx = cx + random.uniform(-8, 8)
        blade_h = random.uniform(60, 90)
        tip_x = bx + angle * 50
        tip_y = cy_base - blade_h

        ctx.set_line_width(3)
        ctx.move_to(bx, cy_base)
        ctx.curve_to(bx + angle * 15, cy_base - blade_h * 0.4,
                     tip_x * 0.7 + bx * 0.3, tip_y + 15,
                     tip_x, tip_y)
        set_color(ctx, LEAF_MED, 0.6)
        ctx.stroke()

    save_surface(surface, "cattail.png")


def generate_mushroom_small(w=128, h=128):
    """Small mushroom with round cap, blue with gold spots."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    # ── Short stem ──
    stem_w, stem_h = 10, 35
    stem_x = cx - stem_w / 2
    stem_y = cy_base - stem_h

    STEM_L = (0.55, 0.58, 0.75)
    STEM_D = (0.35, 0.38, 0.58)

    pat = cairo.LinearGradient(stem_x, stem_y, stem_x, stem_y + stem_h)
    pat.add_color_stop_rgb(0, *STEM_L)
    pat.add_color_stop_rgb(1, *STEM_D)
    # Slight bulge
    ctx.move_to(cx - stem_w * 0.4, stem_y)
    ctx.curve_to(cx - stem_w * 0.55, stem_y + stem_h * 0.5,
                 cx - stem_w * 0.5, stem_y + stem_h * 0.8,
                 cx - stem_w * 0.6, stem_y + stem_h)
    ctx.line_to(cx + stem_w * 0.6, stem_y + stem_h)
    ctx.curve_to(cx + stem_w * 0.5, stem_y + stem_h * 0.8,
                 cx + stem_w * 0.55, stem_y + stem_h * 0.5,
                 cx + stem_w * 0.4, stem_y)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # ── Round cap ──
    cap_cy = stem_y + 5
    cap_rx = 30
    cap_ry = 22

    pat = cairo.RadialGradient(cx - 8, cap_cy - cap_ry * 0.4, cap_ry * 0.1,
                               cx, cap_cy, cap_rx)
    pat.add_color_stop_rgb(0, *LEAF_BRIGHT)
    pat.add_color_stop_rgb(0.6, *LEAF_MED)
    pat.add_color_stop_rgb(1, *LEAF_DARK)

    ctx.save()
    ctx.translate(cx, cap_cy)
    ctx.scale(cap_rx, cap_ry)
    ctx.arc(0, 0, 1, math.pi, 0)
    ctx.restore()
    ctx.set_source(pat)
    ctx.fill()

    # Underside
    ctx.save()
    ctx.translate(cx, cap_cy)
    ctx.scale(cap_rx * 0.9, cap_ry * 0.2)
    ctx.arc(0, 0, 1, 0, math.pi)
    ctx.restore()
    set_color(ctx, LEAF_SHADOW, 0.5)
    ctx.fill()

    # Gold spots on cap
    for _ in range(5):
        sx = cx + random.uniform(-cap_rx * 0.6, cap_rx * 0.6)
        sy = cap_cy - random.uniform(cap_ry * 0.2, cap_ry * 0.8)
        sr = random.uniform(3, 6)
        draw_circle(ctx, sx, sy, sr, GOLD_PRIMARY, random.uniform(0.5, 0.8))
        draw_circle(ctx, sx - 0.5, sy - 0.5, sr * 0.4, GOLD_BRIGHT, 0.4)

    save_surface(surface, "mushroom_small.png")


def generate_crystal_cluster(w=128, h=128):
    """Cluster of angular crystal shapes, bright blue with gold sparkle tips."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 5

    # Crystal spires
    crystals = [
        (cx - 25, cy_base, 14, 65),   # (base_x, base_y, half_width, height)
        (cx, cy_base, 18, 85),
        (cx + 22, cy_base, 12, 55),
        (cx - 12, cy_base, 10, 45),
        (cx + 35, cy_base, 8, 40),
        (cx + 10, cy_base, 15, 70),
    ]

    for base_x, base_y, hw, ch in crystals:
        tip_y = base_y - ch

        # Crystal body gradient
        pat = cairo.LinearGradient(base_x - hw, tip_y, base_x + hw, base_y)
        pat.add_color_stop_rgba(0, *LEAF_BRIGHT, 0.9)
        pat.add_color_stop_rgba(0.3, *BLUE_LIGHT, 0.85)
        pat.add_color_stop_rgba(0.7, *LEAF_MED, 0.8)
        pat.add_color_stop_rgba(1, *LEAF_DARK, 0.75)

        # Angular crystal shape (hexagonal cross-section illusion)
        mid_y = (tip_y + base_y) / 2
        ctx.move_to(base_x, tip_y)
        ctx.line_to(base_x + hw, mid_y)
        ctx.line_to(base_x + hw * 0.7, base_y)
        ctx.line_to(base_x - hw * 0.7, base_y)
        ctx.line_to(base_x - hw, mid_y)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()

        # Light edge highlight
        ctx.set_line_width(1.0)
        ctx.move_to(base_x, tip_y)
        ctx.line_to(base_x - hw, mid_y)
        set_color(ctx, WHITE, 0.4)
        ctx.stroke()

        # Facet line
        ctx.move_to(base_x, tip_y)
        ctx.line_to(base_x, base_y)
        set_color(ctx, LEAF_BRIGHT, 0.3)
        ctx.stroke()

        # Gold sparkle tip
        draw_circle(ctx, base_x, tip_y, 3, GOLD_BRIGHT, 0.8)
        draw_circle(ctx, base_x, tip_y, 1.5, GOLD_METAL, 1.0)

    # Gold sparkle particles around
    for _ in range(6):
        sx = cx + random.uniform(-40, 40)
        sy = cy_base - random.uniform(20, 80)
        draw_circle(ctx, sx, sy, 1.5, GOLD_BRIGHT, random.uniform(0.3, 0.7))

    save_surface(surface, "crystal_cluster.png")


def generate_log(w=128, h=128):
    """Fallen log lying horizontal, blue-bark colored with moss patches."""
    surface, ctx = make_surface(w, h)
    cy = h * 0.6

    # ── Horizontal log ──
    log_left = 8
    log_right = w - 8
    log_h = 24

    # Main body
    pat = cairo.LinearGradient(log_left, cy - log_h / 2, log_left, cy + log_h / 2)
    pat.add_color_stop_rgb(0, *BARK_MED)
    pat.add_color_stop_rgb(0.5, *BARK_DARK)
    pat.add_color_stop_rgb(1, *BARK_SHADOW)

    # Rounded rectangle
    r = log_h / 2
    ctx.move_to(log_left + r, cy - log_h / 2)
    ctx.line_to(log_right - r, cy - log_h / 2)
    ctx.arc(log_right - r, cy, r, -math.pi / 2, math.pi / 2)
    ctx.line_to(log_left + r, cy + log_h / 2)
    ctx.arc(log_left + r, cy, r, math.pi / 2, 3 * math.pi / 2)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Cross-section circle at right end (cut end)
    end_cx = log_right - r + 2
    draw_radial_circle(ctx, end_cx, cy, r - 1, BARK_LIGHT, BARK_MED)
    # Ring detail
    draw_circle(ctx, end_cx, cy, r * 0.6, BARK_MED, 0.5)
    draw_circle(ctx, end_cx, cy, r * 0.3, BARK_DARK, 0.5)
    draw_circle(ctx, end_cx, cy, 2, BARK_SHADOW, 0.8)

    # Bark texture lines
    ctx.set_line_width(0.8)
    for _ in range(10):
        bx = random.uniform(log_left + r, log_right - r)
        ctx.move_to(bx, cy - log_h / 2 + 2)
        ctx.line_to(bx + random.uniform(-2, 2), cy + log_h / 2 - 2)
        set_color(ctx, BARK_SHADOW, 0.3)
        ctx.stroke()

    # Moss patches on top (blue-green → blue since we're all-blue)
    for _ in range(4):
        mx = random.uniform(log_left + 15, log_right - 15)
        my = cy - log_h / 2 + random.uniform(-2, 3)
        mr = random.uniform(5, 10)
        draw_circle(ctx, mx, my, mr, LEAF_MED, 0.5)
        # Tiny highlight dots
        for __ in range(3):
            draw_circle(ctx, mx + random.uniform(-4, 4), my + random.uniform(-3, 2),
                       1.5, LEAF_BRIGHT, 0.4)

    # Small mushroom growing on log (gold accent)
    mush_x = random.uniform(log_left + 30, log_right - 30)
    mush_y = cy - log_h / 2 - 2
    draw_circle(ctx, mush_x, mush_y - 6, 5, LEAF_MED, 0.7)
    draw_circle(ctx, mush_x, mush_y - 5, 2, GOLD_PRIMARY, 0.5)
    ctx.set_line_width(1.5)
    ctx.move_to(mush_x, mush_y)
    ctx.line_to(mush_x, mush_y - 4)
    set_color(ctx, BARK_LIGHT, 0.6)
    ctx.stroke()

    save_surface(surface, "log.png")


def generate_stump(w=128, h=128):
    """Tree stump — flat top with ring detail, blue bark sides."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 10

    stump_w = 35
    stump_h = 45
    stump_top = cy_base - stump_h

    # ── Bark sides ──
    pat = cairo.LinearGradient(cx - stump_w, stump_top, cx + stump_w, cy_base)
    pat.add_color_stop_rgb(0, *BARK_MED)
    pat.add_color_stop_rgb(1, *BARK_SHADOW)

    # Slightly tapered
    ctx.move_to(cx - stump_w * 0.85, stump_top)
    ctx.line_to(cx - stump_w, cy_base)
    ctx.line_to(cx + stump_w, cy_base)
    ctx.line_to(cx + stump_w * 0.85, stump_top)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    draw_bark_texture(ctx, cx - stump_w, stump_top, stump_w * 2, stump_h, BARK_SHADOW, 15)

    # ── Flat top (ellipse with rings) ──
    top_rx = stump_w * 0.9
    top_ry = 12

    # Top face
    ctx.save()
    ctx.translate(cx, stump_top)
    ctx.scale(top_rx, top_ry)
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.restore()
    set_color(ctx, BARK_LIGHT)
    ctx.fill()

    # Growth rings
    for ring_r in [0.8, 0.6, 0.4, 0.2]:
        ctx.save()
        ctx.translate(cx, stump_top)
        ctx.scale(top_rx * ring_r, top_ry * ring_r)
        ctx.arc(0, 0, 1, 0, 2 * math.pi)
        ctx.restore()
        ctx.set_line_width(1.0)
        set_color(ctx, BARK_MED, 0.5)
        ctx.stroke()

    # Center dot
    draw_circle(ctx, cx, stump_top, 2, BARK_DARK, 0.7)

    # Tiny mushroom growing on side
    m_side = random.choice([-1, 1])
    mx = cx + m_side * stump_w * 0.7
    my = stump_top + stump_h * 0.4
    draw_circle(ctx, mx + m_side * 5, my, 4, LEAF_MED, 0.6)
    draw_circle(ctx, mx + m_side * 5, my, 1.5, GOLD_PRIMARY, 0.4)

    # Root flares at base
    for side in [-1, 1]:
        ctx.set_line_width(4)
        ctx.move_to(cx + side * stump_w, cy_base)
        ctx.curve_to(cx + side * (stump_w + 10), cy_base + 2,
                     cx + side * (stump_w + 15), cy_base + 1,
                     cx + side * (stump_w + 12), cy_base + 5)
        set_color(ctx, BARK_SHADOW)
        ctx.stroke()

    save_surface(surface, "stump.png")


# ── New rock generators ────────────────────────────────────────────────────

def generate_rock_mossy(w=96, h=96):
    """Rock with blue-moss patches on top."""
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.55

    # Main rock shape (same as regular rock)
    rx, ry = 38, 28
    pat = cairo.RadialGradient(cx - 10, cy - 10, 5, cx, cy, 40)
    pat.add_color_stop_rgb(0, *GRAY_LIGHT)
    pat.add_color_stop_rgb(0.6, *GRAY_MED)
    pat.add_color_stop_rgb(1, *GRAY_DARK)

    ctx.move_to(cx - rx, cy + 5)
    ctx.curve_to(cx - rx - 3, cy - ry * 0.5, cx - rx * 0.4, cy - ry, cx, cy - ry + 2)
    ctx.curve_to(cx + rx * 0.5, cy - ry - 3, cx + rx + 2, cy - ry * 0.4, cx + rx, cy + 3)
    ctx.curve_to(cx + rx + 1, cy + ry * 0.6, cx + rx * 0.3, cy + ry, cx - 5, cy + ry - 2)
    ctx.curve_to(cx - rx * 0.5, cy + ry + 1, cx - rx - 2, cy + ry * 0.3, cx - rx, cy + 5)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Crack lines
    ctx.set_line_width(1.0)
    for x0, y0, x1, y1 in [(cx - 10, cy - 8, cx + 5, cy + 3), (cx + 8, cy - 5, cx + 12, cy + 6)]:
        ctx.move_to(x0, y0)
        ctx.curve_to(x0 + 3, y0 + 4, x1 - 2, y1 - 2, x1, y1)
        set_color(ctx, GRAY_DARK, 0.5)
        ctx.stroke()

    # Moss patches on top (blue leaf colors)
    moss_patches = [
        (cx - 10, cy - ry + 8, 12),
        (cx + 8, cy - ry + 10, 10),
        (cx - 2, cy - ry + 5, 14),
        (cx + 15, cy - ry + 12, 8),
    ]
    for mx, my, mr in moss_patches:
        draw_circle(ctx, mx, my, mr, LEAF_MED, 0.6)
        # Moss highlight dots
        for _ in range(4):
            draw_circle(ctx, mx + random.uniform(-mr * 0.6, mr * 0.6),
                       my + random.uniform(-mr * 0.5, mr * 0.3),
                       random.uniform(1, 3), LEAF_BRIGHT, 0.4)

    save_surface(surface, "rock_mossy.png")


def generate_rock_crystal(w=96, h=96):
    """Angular crystal-studded rock with bright blue facets and gold veins."""
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.55

    # Base rock (darker, more angular)
    rx, ry = 36, 26
    pat = cairo.RadialGradient(cx - 8, cy - 8, 3, cx, cy, 38)
    pat.add_color_stop_rgb(0, *GRAY_MED)
    pat.add_color_stop_rgb(0.6, *GRAY_DARK)
    pat.add_color_stop_rgb(1, 0.08, 0.10, 0.20)

    # More angular shape
    ctx.move_to(cx - rx, cy + 3)
    ctx.line_to(cx - rx * 0.6, cy - ry)
    ctx.line_to(cx + rx * 0.3, cy - ry - 2)
    ctx.line_to(cx + rx, cy - ry * 0.3)
    ctx.line_to(cx + rx - 2, cy + ry * 0.7)
    ctx.line_to(cx - rx * 0.2, cy + ry)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Gold veins
    ctx.set_line_width(1.5)
    veins = [
        (cx - 15, cy - 10, cx + 10, cy + 5),
        (cx - 5, cy - ry + 5, cx + 5, cy + 3),
        (cx + 5, cy - 5, cx + rx - 8, cy + 5),
    ]
    for x0, y0, x1, y1 in veins:
        ctx.move_to(x0, y0)
        ctx.curve_to(x0 + random.uniform(-5, 5), (y0 + y1) / 2,
                     x1 + random.uniform(-5, 5), (y0 + y1) / 2,
                     x1, y1)
        set_color(ctx, GOLD_PRIMARY, 0.6)
        ctx.stroke()

    # Crystal protrusions
    crystals_on_rock = [
        (cx - 10, cy - ry + 2, 6, 18),
        (cx + 12, cy - ry + 5, 5, 14),
        (cx + 2, cy - ry - 2, 7, 22),
    ]
    for bx, by, hw, ch in crystals_on_rock:
        tip_y = by - ch
        pat = cairo.LinearGradient(bx, tip_y, bx, by)
        pat.add_color_stop_rgba(0, *LEAF_BRIGHT, 0.9)
        pat.add_color_stop_rgba(0.5, *BLUE_LIGHT, 0.85)
        pat.add_color_stop_rgba(1, *LEAF_MED, 0.7)

        mid_y = (tip_y + by) / 2
        ctx.move_to(bx, tip_y)
        ctx.line_to(bx + hw, mid_y)
        ctx.line_to(bx + hw * 0.6, by)
        ctx.line_to(bx - hw * 0.6, by)
        ctx.line_to(bx - hw, mid_y)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()

        # Gold sparkle tip
        draw_circle(ctx, bx, tip_y, 2, GOLD_BRIGHT, 0.8)

    save_surface(surface, "rock_crystal.png")


def generate_boulder(w=96, h=96):
    """Large rounded boulder — will be scaled up in spawner."""
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.52

    # Larger, rounder shape
    rx, ry = 42, 34
    pat = cairo.RadialGradient(cx - 12, cy - 12, 5, cx, cy, 44)
    pat.add_color_stop_rgb(0, *GRAY_LIGHT)
    pat.add_color_stop_rgb(0.5, *GRAY_MED)
    pat.add_color_stop_rgb(1, *GRAY_DARK)

    # Smooth rounded shape
    ctx.save()
    ctx.translate(cx, cy)
    ctx.scale(rx, ry)
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.restore()
    ctx.set_source(pat)
    ctx.fill()

    # Surface cracks
    ctx.set_line_width(1.2)
    for _ in range(3):
        x0 = cx + random.uniform(-rx * 0.5, rx * 0.5)
        y0 = cy + random.uniform(-ry * 0.5, ry * 0.5)
        x1 = x0 + random.uniform(-15, 15)
        y1 = y0 + random.uniform(-10, 10)
        ctx.move_to(x0, y0)
        ctx.curve_to(x0 + 3, y0 + 3, x1 - 3, y1 - 2, x1, y1)
        set_color(ctx, GRAY_DARK, 0.4)
        ctx.stroke()

    # Highlight on upper-left
    glow = cairo.RadialGradient(cx - rx * 0.3, cy - ry * 0.3, 2,
                                cx - rx * 0.3, cy - ry * 0.3, rx * 0.5)
    glow.add_color_stop_rgba(0, *WHITE, 0.2)
    glow.add_color_stop_rgba(1, *WHITE, 0.0)
    ctx.arc(cx, cy, rx, 0, 2 * math.pi)
    ctx.set_source(glow)
    ctx.fill()

    # Subtle gold fleck
    draw_circle(ctx, cx + 10, cy + 8, 5, GOLD_DARK, 0.2)

    save_surface(surface, "boulder.png")


# ── Forageable generators ────────────────────────────────────────────────────

def generate_pinkberry_bush(w=128, h=128):
    """Small bush with bright pink berry clusters on blue foliage."""
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.6

    # Dark blue stems
    ctx.set_line_width(2.5)
    for angle in [-0.4, -0.1, 0.15, 0.35]:
        ctx.move_to(cx + angle * 12, h - 8)
        ctx.line_to(cx + angle * 20, cy + 8)
        set_color(ctx, BARK_SHADOW)
        ctx.stroke()

    # Blue leaf clusters (smaller than regular bush)
    blobs = [
        (cx, cy, 24),
        (cx - 22, cy + 6, 18),
        (cx + 22, cy + 6, 18),
        (cx - 12, cy - 12, 16),
        (cx + 12, cy - 12, 16),
        (cx, cy + 12, 20),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_MED, LEAF_DARK)

    # Highlight on top blobs
    for bx, by, br in blobs[:2]:
        draw_radial_circle(ctx, bx - 2, by - 2, br * 0.35,
                           LEAF_BRIGHT, LEAF_MED, 0.5, 0.0)

    # Bright pink berries (main feature)
    BERRY_BRIGHT = (1.0, 0.45, 0.65)
    BERRY_MID = (0.9, 0.3, 0.5)
    BERRY_DARK = (0.6, 0.15, 0.35)
    for _ in range(12):
        bx = cx + random.uniform(-26, 26)
        by = cy + random.uniform(-14, 14)
        br = random.uniform(3, 5.5)
        draw_radial_circle(ctx, bx, by, br, BERRY_BRIGHT, BERRY_DARK, 0.9, 0.9)
        # Tiny highlight
        draw_circle(ctx, bx - 1, by - 1, br * 0.3, WHITE, 0.6)

    save_surface(surface, "pinkberry_bush.png")


def generate_rootbeer_plant(w=128, h=128):
    """Thick gnarly brown-blue root partially unearthed, with small blue leaves."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    # Root body - thick bulbous shape (dark blue-brown)
    ROOT_LIGHT = (0.35, 0.28, 0.55)
    ROOT_MID = (0.22, 0.18, 0.42)
    ROOT_DARK = (0.12, 0.10, 0.30)

    # Main root bulb
    root_top_y = cy_base - 35
    ctx.move_to(cx - 14, root_top_y + 5)
    ctx.curve_to(cx - 16, root_top_y + 15, cx - 12, cy_base - 5, cx - 4, cy_base + 2)
    ctx.line_to(cx + 4, cy_base + 2)
    ctx.curve_to(cx + 12, cy_base - 5, cx + 16, root_top_y + 15, cx + 14, root_top_y + 5)
    ctx.close_path()
    pat = cairo.LinearGradient(cx - 14, root_top_y, cx + 14, cy_base)
    pat.add_color_stop_rgb(0, *ROOT_LIGHT)
    pat.add_color_stop_rgb(0.5, *ROOT_MID)
    pat.add_color_stop_rgb(1, *ROOT_DARK)
    ctx.set_source(pat)
    ctx.fill()

    # Root texture lines (horizontal rings)
    ctx.set_line_width(0.7)
    for i in range(4):
        y = root_top_y + 10 + i * 7
        spread = 10 - i * 1.5
        ctx.move_to(cx - spread, y)
        ctx.line_to(cx + spread, y)
        set_color(ctx, ROOT_DARK, 0.5)
        ctx.stroke()

    # Small rootlets dangling below
    ctx.set_line_width(1.5)
    for dx in [-6, -2, 3, 7]:
        ctx.move_to(cx + dx, cy_base)
        ctx.curve_to(cx + dx + 2, cy_base + 6, cx + dx - 1, cy_base + 10, cx + dx + 1, cy_base + 14)
        set_color(ctx, ROOT_DARK, 0.6)
        ctx.stroke()

    # Small blue leaves sprouting from top
    for angle_offset in [-0.5, -0.15, 0.2, 0.45]:
        leaf_tip_x = cx + angle_offset * 28
        leaf_tip_y = root_top_y - 30 + abs(angle_offset) * 10
        ctx.move_to(cx, root_top_y + 5)
        ctx.curve_to(cx + angle_offset * 8, root_top_y - 10,
                     leaf_tip_x - angle_offset * 4, leaf_tip_y + 8,
                     leaf_tip_x, leaf_tip_y)
        ctx.line_to(leaf_tip_x + 1.5, leaf_tip_y + 2)
        ctx.curve_to(leaf_tip_x - angle_offset * 2, leaf_tip_y + 12,
                     cx + angle_offset * 6, root_top_y - 5,
                     cx, root_top_y + 5)
        ctx.close_path()
        shade = random.uniform(0, 0.12)
        set_color(ctx, (LEAF_MED[0] + shade, LEAF_MED[1] + shade, LEAF_MED[2]))
        ctx.fill()

    # Gold sparkle on the root (it's special/magical)
    for _ in range(3):
        sx = cx + random.uniform(-10, 10)
        sy = root_top_y + random.uniform(8, 28)
        draw_circle(ctx, sx, sy, 1.5, GOLD_BRIGHT, 0.7)

    save_surface(surface, "rootbeer_plant.png")


def generate_shadow_mushroom(w=128, h=128):
    """Dark blue mushroom cluster with faint gold spots."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    DARK_CAP = (0.06, 0.08, 0.28)
    DARK_CAP_LIGHT = (0.12, 0.16, 0.42)
    DARK_STEM = (0.15, 0.18, 0.35)

    # Draw 3 mushrooms of different sizes
    mushrooms = [
        (cx - 18, cy_base, 0.7),
        (cx + 15, cy_base, 0.85),
        (cx, cy_base, 1.0),
    ]
    for mx, my, scale in mushrooms:
        stem_w = 8 * scale
        stem_h = 30 * scale
        stem_y = my - stem_h

        # Stem
        pat = cairo.LinearGradient(mx, stem_y, mx, my)
        pat.add_color_stop_rgb(0, *DARK_STEM)
        pat.add_color_stop_rgb(1, *(DARK_STEM[0] * 0.7, DARK_STEM[1] * 0.7, DARK_STEM[2] * 0.7))
        ctx.move_to(mx - stem_w * 0.4, stem_y + 3)
        ctx.line_to(mx - stem_w * 0.55, my)
        ctx.line_to(mx + stem_w * 0.55, my)
        ctx.line_to(mx + stem_w * 0.4, stem_y + 3)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()

        # Cap
        cap_rx = 22 * scale
        cap_ry = 16 * scale
        cap_cy = stem_y + 5 * scale

        pat = cairo.RadialGradient(mx - 5 * scale, cap_cy - cap_ry * 0.3, cap_ry * 0.1,
                                   mx, cap_cy, cap_rx)
        pat.add_color_stop_rgb(0, *DARK_CAP_LIGHT)
        pat.add_color_stop_rgb(1, *DARK_CAP)
        ctx.save()
        ctx.translate(mx, cap_cy)
        ctx.scale(cap_rx, cap_ry)
        ctx.arc(0, 0, 1, math.pi, 0)
        ctx.restore()
        ctx.set_source(pat)
        ctx.fill()

        # Faint gold spots
        for _ in range(3):
            sx = mx + random.uniform(-cap_rx * 0.5, cap_rx * 0.5)
            sy = cap_cy - random.uniform(cap_ry * 0.2, cap_ry * 0.7)
            sr = random.uniform(2, 4) * scale
            draw_circle(ctx, sx, sy, sr, GOLD_DARK, random.uniform(0.2, 0.4))

    save_surface(surface, "shadow_mushroom.png")


def generate_nightshade_bush(w=128, h=128):
    """Dark spiky bush with small purple-blue berries."""
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.6

    NIGHTSHADE_DARK = (0.05, 0.04, 0.22)
    NIGHTSHADE_MED = (0.1, 0.08, 0.35)
    BERRY_PURPLE = (0.3, 0.15, 0.55)
    BERRY_BRIGHT = (0.45, 0.25, 0.7)

    # Spiky dark stems
    ctx.set_line_width(2)
    for angle in [-0.6, -0.3, 0.0, 0.3, 0.6]:
        tip_x = cx + angle * 40
        tip_y = cy - 25 + abs(angle) * 10
        ctx.move_to(cx + angle * 5, h - 8)
        ctx.line_to(tip_x, tip_y)
        set_color(ctx, NIGHTSHADE_DARK)
        ctx.stroke()

    # Dark leaf blobs
    blobs = [
        (cx, cy, 22),
        (cx - 20, cy + 5, 16),
        (cx + 20, cy + 5, 16),
        (cx - 10, cy - 14, 14),
        (cx + 10, cy - 14, 14),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, NIGHTSHADE_MED, NIGHTSHADE_DARK)

    # Spiky tips
    for _ in range(8):
        sx = cx + random.uniform(-28, 28)
        sy = cy + random.uniform(-20, 10)
        length = random.uniform(8, 15)
        angle = random.uniform(-math.pi, -0.3)
        ctx.move_to(sx, sy)
        ctx.line_to(sx + math.cos(angle) * length, sy + math.sin(angle) * length)
        ctx.set_line_width(1.5)
        set_color(ctx, NIGHTSHADE_DARK)
        ctx.stroke()

    # Purple berries
    for _ in range(6):
        bx = cx + random.uniform(-22, 22)
        by = cy + random.uniform(-10, 12)
        br = random.uniform(2.5, 4)
        draw_radial_circle(ctx, bx, by, br, BERRY_BRIGHT, BERRY_PURPLE, 0.85, 0.85)
        draw_circle(ctx, bx - 0.5, by - 0.5, br * 0.25, WHITE, 0.3)

    save_surface(surface, "nightshade_bush.png")


def generate_frost_berry_bush(w=128, h=128):
    """Icy blue bush with bright pale blue berries and frost crystals."""
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.6

    ICY_LIGHT = (0.65, 0.75, 1.0)
    ICY_MED = (0.4, 0.55, 0.9)
    ICY_DARK = (0.2, 0.35, 0.7)
    FROST_WHITE = (0.85, 0.9, 1.0)

    # Stems
    ctx.set_line_width(2)
    for angle in [-0.35, -0.1, 0.15, 0.4]:
        ctx.move_to(cx + angle * 10, h - 8)
        ctx.line_to(cx + angle * 22, cy + 5)
        set_color(ctx, ICY_DARK)
        ctx.stroke()

    # Icy leaf blobs
    blobs = [
        (cx, cy, 25),
        (cx - 24, cy + 5, 18),
        (cx + 24, cy + 5, 18),
        (cx - 12, cy - 14, 17),
        (cx + 12, cy - 14, 17),
        (cx, cy + 14, 20),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, ICY_MED, ICY_DARK)

    # Frost highlights
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx - 2, by - 2, br * 0.3,
                           FROST_WHITE, ICY_LIGHT, 0.4, 0.0)

    # Pale blue berries
    for _ in range(8):
        bx = cx + random.uniform(-26, 26)
        by = cy + random.uniform(-12, 12)
        br = random.uniform(3, 5)
        draw_radial_circle(ctx, bx, by, br, FROST_WHITE, ICY_LIGHT, 0.9, 0.8)
        draw_circle(ctx, bx - 1, by - 1, br * 0.3, WHITE, 0.6)

    # Small frost crystal accents
    ctx.set_line_width(1.0)
    for _ in range(4):
        fx = cx + random.uniform(-20, 20)
        fy = cy + random.uniform(-18, 8)
        for a in range(6):
            angle = a * math.pi / 3
            ctx.move_to(fx, fy)
            ctx.line_to(fx + math.cos(angle) * 4, fy + math.sin(angle) * 4)
        set_color(ctx, FROST_WHITE, 0.5)
        ctx.stroke()

    save_surface(surface, "frost_berry_bush.png")


def generate_sage_plant(w=128, h=128):
    """Tall desert herb with gold-tipped leaves."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    # Main stem
    ctx.set_line_width(3)
    ctx.move_to(cx, cy_base)
    ctx.line_to(cx, cy_base - 70)
    set_color(ctx, BARK_MED)
    ctx.stroke()

    # Side stems
    stems = [
        (cx, cy_base - 20, cx - 25, cy_base - 40),
        (cx, cy_base - 30, cx + 22, cy_base - 50),
        (cx, cy_base - 45, cx - 18, cy_base - 60),
        (cx, cy_base - 55, cx + 15, cy_base - 70),
    ]
    ctx.set_line_width(2)
    for x0, y0, x1, y1 in stems:
        ctx.move_to(x0, y0)
        ctx.line_to(x1, y1)
        set_color(ctx, BARK_MED)
        ctx.stroke()

    # Leaves with gold tips
    for x0, y0, x1, y1 in stems:
        # Leaf shape
        ctx.move_to(x1, y1)
        ctx.curve_to(x1 - 8, y1 - 5, x1 + 8, y1 - 12, x1, y1 - 18)
        ctx.curve_to(x1 + 8, y1 - 5, x1 - 8, y1 + 2, x1, y1)
        ctx.close_path()
        set_color(ctx, LEAF_MED)
        ctx.fill()

        # Gold tip
        draw_circle(ctx, x1, y1 - 16, 3, GOLD_PRIMARY, 0.8)
        draw_circle(ctx, x1, y1 - 16, 1.5, GOLD_BRIGHT, 0.5)

    # Top leaves with gold
    for offset in [-6, 0, 6]:
        tip_y = cy_base - 80
        ctx.move_to(cx + offset, cy_base - 65)
        ctx.curve_to(cx + offset - 5, tip_y + 5, cx + offset + 5, tip_y + 2, cx + offset, tip_y)
        ctx.curve_to(cx + offset + 5, tip_y + 5, cx + offset - 5, tip_y + 8, cx + offset, cy_base - 65)
        ctx.close_path()
        set_color(ctx, LEAF_LIGHT)
        ctx.fill()
        draw_circle(ctx, cx + offset, tip_y, 2.5, GOLD_PRIMARY, 0.7)

    save_surface(surface, "sage_plant.png")


def generate_mana_fruit_tree(w=128, h=128):
    """Small tree with glowing blue-gold fruits."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 5

    # Short trunk
    trunk_w, trunk_h = 12, 40
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h
    draw_trunk_gradient(ctx, trunk_x, trunk_y, trunk_w, trunk_h,
                        BARK_MED, BARK_DARK)

    # Small root flare
    for side in [-1, 1]:
        ctx.move_to(cx + side * trunk_w / 2, cy_base)
        ctx.line_to(cx + side * (trunk_w / 2 + 6), cy_base + 2)
        ctx.line_to(cx + side * trunk_w / 2, cy_base - 5)
        ctx.close_path()
        set_color(ctx, BARK_DARK)
        ctx.fill()

    # Canopy blobs
    canopy_cy = trunk_y - 5
    blobs = [
        (cx, canopy_cy, 28),
        (cx - 22, canopy_cy + 5, 20),
        (cx + 22, canopy_cy + 5, 20),
        (cx - 10, canopy_cy - 18, 17),
        (cx + 10, canopy_cy - 18, 17),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, LEAF_LIGHT, LEAF_DARK)

    # Highlights
    for bx, by, br in blobs[:2]:
        draw_radial_circle(ctx, bx - 3, by - 3, br * 0.35,
                           LEAF_BRIGHT, LEAF_MED, 0.4, 0.0)

    # Glowing mana fruits (blue-gold)
    for _ in range(5):
        fx = cx + random.uniform(-24, 24)
        fy = canopy_cy + random.uniform(-12, 12)
        fr = random.uniform(4, 6)
        # Outer glow
        draw_radial_circle(ctx, fx, fy, fr * 2.0,
                           GOLD_BRIGHT, BLUE_LIGHT, 0.2, 0.0)
        # Fruit body
        draw_radial_circle(ctx, fx, fy, fr, GOLD_BRIGHT, GOLD_PRIMARY, 0.9, 0.85)
        # Highlight
        draw_circle(ctx, fx - 1, fy - 1, fr * 0.3, GOLD_SPEC, 0.6)

    save_surface(surface, "mana_fruit_tree.png")


def generate_ember_pepper_plant(w=128, h=128):
    """Dark plant with bright gold pepper shapes."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    EMBER_DARK = (0.06, 0.03, 0.15)
    EMBER_STEM = (0.1, 0.06, 0.22)

    # Main stem
    ctx.set_line_width(3)
    ctx.move_to(cx, cy_base)
    ctx.curve_to(cx - 3, cy_base - 25, cx + 3, cy_base - 50, cx, cy_base - 65)
    set_color(ctx, EMBER_STEM)
    ctx.stroke()

    # Side branches
    branches = [
        (cx, cy_base - 20, cx - 25, cy_base - 35),
        (cx, cy_base - 30, cx + 28, cy_base - 42),
        (cx, cy_base - 45, cx - 20, cy_base - 55),
        (cx, cy_base - 55, cx + 18, cy_base - 65),
    ]
    ctx.set_line_width(2)
    for x0, y0, x1, y1 in branches:
        ctx.move_to(x0, y0)
        ctx.line_to(x1, y1)
        set_color(ctx, EMBER_STEM)
        ctx.stroke()

    # Dark leaves
    for x0, y0, x1, y1 in branches:
        ctx.move_to(x1, y1)
        dx = (x1 - x0) * 0.3
        ctx.curve_to(x1 + dx - 5, y1 - 8, x1 + dx + 5, y1 - 3, x1, y1)
        set_color(ctx, EMBER_DARK, 0.7)
        ctx.fill()

    # Pepper shapes (gold, elongated)
    peppers = [
        (cx - 22, cy_base - 33, -0.3),
        (cx + 25, cy_base - 40, 0.2),
        (cx - 17, cy_base - 53, -0.15),
        (cx + 15, cy_base - 63, 0.25),
        (cx + 3, cy_base - 70, 0.0),
    ]
    for px, py, tilt in peppers:
        ctx.save()
        ctx.translate(px, py)
        ctx.rotate(tilt)
        # Pepper body
        ctx.move_to(0, -8)
        ctx.curve_to(-5, -6, -5, 6, -1, 10)
        ctx.line_to(1, 10)
        ctx.curve_to(5, 6, 5, -6, 0, -8)
        ctx.close_path()
        pat = cairo.LinearGradient(0, -8, 0, 10)
        pat.add_color_stop_rgb(0, *GOLD_BRIGHT)
        pat.add_color_stop_rgb(0.5, *GOLD_PRIMARY)
        pat.add_color_stop_rgb(1, *GOLD_DARK)
        ctx.set_source(pat)
        ctx.fill()
        # Stem cap
        draw_circle(ctx, 0, -9, 3, EMBER_STEM, 0.8)
        # Highlight
        draw_circle(ctx, -1, -3, 1.5, GOLD_SPEC, 0.4)
        ctx.restore()

    save_surface(surface, "ember_pepper_plant.png")


def generate_truffle_spot(w=128, h=128):
    """Small dirt mound with a truffle peeking out, gold-brown tones."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 15

    # Dirt mound
    ctx.save()
    ctx.translate(cx, cy_base)
    ctx.scale(35, 12)
    ctx.arc(0, 0, 1, math.pi, 0)
    ctx.restore()
    pat = cairo.RadialGradient(cx - 5, cy_base - 5, 3, cx, cy_base, 35)
    pat.add_color_stop_rgb(0, *BARK_LIGHT)
    pat.add_color_stop_rgb(1, *BARK_DARK)
    ctx.set_source(pat)
    ctx.fill()

    # Dirt texture dots
    for _ in range(15):
        dx = cx + random.uniform(-28, 28)
        dy = cy_base + random.uniform(-8, 0)
        draw_circle(ctx, dx, dy, random.uniform(1, 2.5), BARK_SHADOW, random.uniform(0.2, 0.4))

    # Truffle body (gold-tinted lumpy sphere)
    truffle_cx = cx + 3
    truffle_cy = cy_base - 12
    truffle_r = 14

    draw_radial_circle(ctx, truffle_cx, truffle_cy, truffle_r,
                       GOLD_DARK, BARK_DARK, 0.9, 0.9)
    # Lumpy texture
    for _ in range(6):
        lx = truffle_cx + random.uniform(-8, 8)
        ly = truffle_cy + random.uniform(-8, 5)
        draw_circle(ctx, lx, ly, random.uniform(2, 4), GOLD_PRIMARY, random.uniform(0.15, 0.3))
    # Highlight
    draw_radial_circle(ctx, truffle_cx - 4, truffle_cy - 4, truffle_r * 0.35,
                       GOLD_BRIGHT, GOLD_DARK, 0.35, 0.0)

    save_surface(surface, "truffle_spot.png")


def generate_bog_root_plant(w=128, h=128):
    """Twisted root emerging from ground with blue-dark tones."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    BOG_DARK = (0.08, 0.06, 0.2)
    BOG_MED = (0.15, 0.12, 0.32)
    BOG_LIGHT = (0.22, 0.2, 0.42)

    # Ground line
    ctx.move_to(10, cy_base)
    ctx.line_to(w - 10, cy_base)
    ctx.set_line_width(4)
    set_color(ctx, BOG_DARK, 0.5)
    ctx.stroke()

    # Twisted roots emerging
    roots = [
        (cx - 15, cx - 25, -0.3),
        (cx, cx + 5, 0.1),
        (cx + 18, cx + 30, 0.25),
    ]
    for root_base_x, root_tip_x, curve in roots:
        root_tip_y = cy_base - 55 - random.uniform(0, 15)
        ctx.move_to(root_base_x - 5, cy_base)
        ctx.curve_to(root_base_x - 5 + curve * 20, cy_base - 20,
                     root_tip_x - 3, root_tip_y + 15,
                     root_tip_x - 2, root_tip_y)
        ctx.line_to(root_tip_x + 2, root_tip_y)
        ctx.curve_to(root_tip_x + 3, root_tip_y + 15,
                     root_base_x + 5 + curve * 20, cy_base - 20,
                     root_base_x + 5, cy_base)
        ctx.close_path()
        pat = cairo.LinearGradient(root_base_x, cy_base, root_tip_x, root_tip_y)
        pat.add_color_stop_rgb(0, *BOG_DARK)
        pat.add_color_stop_rgb(0.5, *BOG_MED)
        pat.add_color_stop_rgb(1, *BOG_LIGHT)
        ctx.set_source(pat)
        ctx.fill()

        # Small tendrils
        ctx.set_line_width(1.2)
        for _ in range(2):
            ty = root_tip_y + random.uniform(5, 20)
            tx = root_tip_x + random.uniform(-8, 8)
            ctx.move_to(tx, ty)
            ctx.line_to(tx + random.uniform(-6, 6), ty - random.uniform(5, 10))
            set_color(ctx, BOG_LIGHT, 0.6)
            ctx.stroke()

    save_surface(surface, "bog_root_plant.png")


def generate_marsh_herb_plant(w=128, h=128):
    """Wispy healing herb with blue leaves and gold pollen dots."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    # Multiple thin stems
    ctx.set_line_width(1.8)
    stem_tops = []
    for i in range(5):
        sx = cx + (i - 2) * 12
        top_y = cy_base - 50 - random.uniform(0, 20)
        ctx.move_to(sx, cy_base)
        ctx.curve_to(sx + random.uniform(-5, 5), cy_base - 20,
                     sx + random.uniform(-8, 8), top_y + 15,
                     sx, top_y)
        set_color(ctx, BARK_MED)
        ctx.stroke()
        stem_tops.append((sx, top_y))

    # Leaf pairs along stems
    for sx, top_y in stem_tops:
        for ly in range(int(cy_base - 15), int(top_y + 10), -15):
            for side in [-1, 1]:
                lx = sx + side * 10
                ctx.move_to(sx, ly)
                ctx.curve_to(sx + side * 5, ly - 3, lx, ly - 5, lx, ly - 2)
                ctx.curve_to(lx, ly + 1, sx + side * 5, ly + 2, sx, ly)
                ctx.close_path()
                set_color(ctx, LEAF_MED)
                ctx.fill()

    # Gold pollen dots at tops
    for sx, top_y in stem_tops:
        for _ in range(3):
            px = sx + random.uniform(-4, 4)
            py = top_y + random.uniform(-3, 5)
            draw_circle(ctx, px, py, random.uniform(1.5, 2.5), GOLD_PRIMARY, 0.7)

    save_surface(surface, "marsh_herb_plant.png")


def generate_alpine_herb_plant(w=128, h=128):
    """Mountain herb with pale blue-white flowers and sturdy stems."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    ALPINE_STEM = (0.3, 0.35, 0.55)
    ALPINE_LEAF = (0.35, 0.45, 0.7)
    ALPINE_FLOWER = (0.7, 0.78, 1.0)

    # Sturdy stems
    ctx.set_line_width(2.5)
    stem_data = []
    for i in range(4):
        sx = cx + (i - 1.5) * 14
        top_y = cy_base - 55 - random.uniform(0, 15)
        ctx.move_to(sx, cy_base)
        ctx.line_to(sx + random.uniform(-3, 3), top_y)
        set_color(ctx, ALPINE_STEM)
        ctx.stroke()
        stem_data.append((sx, top_y))

    # Broad leaves
    for sx, top_y in stem_data:
        for ly_offset in [15, 30]:
            ly = cy_base - ly_offset
            for side in [-1, 1]:
                ctx.move_to(sx, ly)
                ctx.curve_to(sx + side * 8, ly - 6,
                             sx + side * 14, ly - 2,
                             sx + side * 12, ly + 3)
                ctx.curve_to(sx + side * 8, ly + 4,
                             sx + side * 3, ly + 2,
                             sx, ly)
                ctx.close_path()
                set_color(ctx, ALPINE_LEAF)
                ctx.fill()

    # Pale blue-white flower clusters at tops
    for sx, top_y in stem_data:
        for _ in range(4):
            fx = sx + random.uniform(-5, 5)
            fy = top_y + random.uniform(-3, 5)
            fr = random.uniform(3, 5)
            draw_radial_circle(ctx, fx, fy, fr, WHITE, ALPINE_FLOWER, 0.8, 0.7)
            draw_circle(ctx, fx, fy, fr * 0.3, GOLD_PRIMARY, 0.5)

    save_surface(surface, "alpine_herb_plant.png")


def generate_arcane_herb_plant(w=128, h=128):
    """Mystical herb with glowing blue stems and gold sparkle tips."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    ARCANE_STEM = (0.15, 0.18, 0.55)
    ARCANE_GLOW = (0.3, 0.35, 0.85)

    # Glowing stems
    stem_data = []
    for i in range(5):
        sx = cx + (i - 2) * 11
        top_y = cy_base - 55 - random.uniform(0, 18)
        # Glow behind stem
        ctx.set_line_width(6)
        ctx.move_to(sx, cy_base)
        ctx.curve_to(sx + random.uniform(-8, 8), cy_base - 25,
                     sx + random.uniform(-5, 5), top_y + 10,
                     sx, top_y)
        set_color(ctx, ARCANE_GLOW, 0.15)
        ctx.stroke()
        # Stem
        ctx.set_line_width(2)
        ctx.move_to(sx, cy_base)
        ctx.curve_to(sx + random.uniform(-8, 8), cy_base - 25,
                     sx + random.uniform(-5, 5), top_y + 10,
                     sx, top_y)
        set_color(ctx, ARCANE_STEM)
        ctx.stroke()
        stem_data.append((sx, top_y))

    # Spiral leaves
    for sx, top_y in stem_data:
        for ly_offset in [12, 28]:
            ly = cy_base - ly_offset
            side = 1 if ly_offset % 2 == 0 else -1
            ctx.move_to(sx, ly)
            ctx.curve_to(sx + side * 6, ly - 8,
                         sx + side * 12, ly - 4,
                         sx + side * 10, ly + 1)
            ctx.line_to(sx, ly)
            ctx.close_path()
            set_color(ctx, LEAF_DARK)
            ctx.fill()

    # Gold sparkle tips
    for sx, top_y in stem_data:
        # Outer glow
        draw_radial_circle(ctx, sx, top_y, 6, GOLD_BRIGHT, ARCANE_GLOW, 0.3, 0.0)
        # Sparkle
        draw_circle(ctx, sx, top_y, 3, GOLD_PRIMARY, 0.85)
        draw_circle(ctx, sx - 0.5, top_y - 0.5, 1.5, GOLD_SPEC, 0.5)

    save_surface(surface, "arcane_herb_plant.png")


def generate_brimstone_plant(w=128, h=128):
    """Dark sulfurous plant with ember-like orange-gold tips."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h - 8

    BRIM_DARK = (0.06, 0.03, 0.12)
    BRIM_STEM = (0.1, 0.06, 0.18)

    # Gnarled stems
    ctx.set_line_width(3)
    stem_data = []
    for i in range(4):
        sx = cx + (i - 1.5) * 15
        top_y = cy_base - 45 - random.uniform(0, 15)
        mid_x = sx + random.uniform(-10, 10)
        ctx.move_to(sx, cy_base)
        ctx.curve_to(mid_x, cy_base - 20, mid_x, top_y + 10, sx + (mid_x - sx) * 0.3, top_y)
        set_color(ctx, BRIM_STEM)
        ctx.stroke()
        stem_data.append((sx + (mid_x - sx) * 0.3, top_y))

    # Dark spiky leaves
    for sx, top_y in stem_data:
        for offset in [-8, 0, 8]:
            ly = top_y + abs(offset) + 5
            ctx.move_to(sx, ly)
            ctx.line_to(sx + offset, ly - 12)
            ctx.line_to(sx + offset * 0.3, ly)
            ctx.close_path()
            set_color(ctx, BRIM_DARK, 0.7)
            ctx.fill()

    # Ember-like glowing tips
    for sx, top_y in stem_data:
        draw_radial_circle(ctx, sx, top_y, 5, GOLD_BRIGHT, GOLD_DARK, 0.7, 0.0)
        draw_circle(ctx, sx, top_y, 2.5, GOLD_PRIMARY, 0.9)

    # Smoke wisps
    ctx.set_line_width(1.0)
    for sx, top_y in stem_data[:2]:
        for _ in range(2):
            wy = top_y - random.uniform(3, 10)
            wx = sx + random.uniform(-5, 5)
            ctx.move_to(wx, wy)
            ctx.curve_to(wx + 3, wy - 5, wx - 3, wy - 10, wx + 1, wy - 14)
            set_color(ctx, GRAY_LIGHT, 0.15)
            ctx.stroke()

    save_surface(surface, "brimstone_plant.png")


def generate_lotus_plant(w=128, h=128):
    """Swamp lotus with broad blue petals and gold center."""
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.55

    LOTUS_LIGHT = (0.45, 0.55, 0.9)
    LOTUS_MED = (0.3, 0.4, 0.75)
    LOTUS_DARK = (0.15, 0.22, 0.5)

    # Stem
    ctx.set_line_width(3)
    ctx.move_to(cx, h - 5)
    ctx.curve_to(cx - 5, cy + 25, cx + 5, cy + 10, cx, cy + 5)
    set_color(ctx, BARK_MED)
    ctx.stroke()

    # Lily pad (flat oval at base)
    ctx.save()
    ctx.translate(cx, h - 12)
    ctx.scale(30, 8)
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.restore()
    set_color(ctx, LEAF_DARK, 0.6)
    ctx.fill()

    # Petals (arranged in circle)
    num_petals = 6
    for i in range(num_petals):
        angle = i * 2 * math.pi / num_petals - math.pi / 2
        px = cx + math.cos(angle) * 18
        py = cy + math.sin(angle) * 12
        # Petal shape
        ctx.move_to(cx, cy)
        ctx.curve_to(cx + math.cos(angle - 0.3) * 12, cy + math.sin(angle - 0.3) * 10,
                     px + math.cos(angle - 0.2) * 8, py + math.sin(angle - 0.2) * 6,
                     px, py)
        ctx.curve_to(px + math.cos(angle + 0.2) * 8, py + math.sin(angle + 0.2) * 6,
                     cx + math.cos(angle + 0.3) * 12, cy + math.sin(angle + 0.3) * 10,
                     cx, cy)
        ctx.close_path()
        shade = i * 0.03
        set_color(ctx, (LOTUS_MED[0] + shade, LOTUS_MED[1] + shade, LOTUS_MED[2]))
        ctx.fill()

    # Inner petals (lighter)
    for i in range(num_petals):
        angle = i * 2 * math.pi / num_petals - math.pi / 2 + math.pi / num_petals
        px = cx + math.cos(angle) * 10
        py = cy + math.sin(angle) * 7
        ctx.move_to(cx, cy)
        ctx.curve_to(cx + math.cos(angle - 0.2) * 6, cy + math.sin(angle - 0.2) * 5,
                     px, py, px, py)
        ctx.curve_to(px, py,
                     cx + math.cos(angle + 0.2) * 6, cy + math.sin(angle + 0.2) * 5,
                     cx, cy)
        ctx.close_path()
        set_color(ctx, LOTUS_LIGHT)
        ctx.fill()

    # Gold center
    draw_radial_circle(ctx, cx, cy, 6, GOLD_BRIGHT, GOLD_PRIMARY, 0.9, 0.8)
    draw_circle(ctx, cx - 1, cy - 1, 2, GOLD_SPEC, 0.5)

    save_surface(surface, "lotus_plant.png")


def generate_golden_tree(w=256, h=512):
    """Golden resin tree — amber/gold trunk with bright gold leaf canopy and metallic highlights."""
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Golden/amber trunk ──
    trunk_w, trunk_h = 28, 200
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 20

    # Warm golden glow behind trunk
    glow = cairo.RadialGradient(cx, trunk_y + trunk_h / 2, trunk_w / 2,
                                cx, trunk_y + trunk_h / 2, trunk_w * 2.5)
    glow.add_color_stop_rgba(0, *GOLD_PRIMARY, 0.2)
    glow.add_color_stop_rgba(1, *GOLD_DARK, 0.0)
    ctx.rectangle(cx - trunk_w * 2.5, trunk_y - 20, trunk_w * 5, trunk_h + 40)
    ctx.set_source(glow)
    ctx.fill()

    # Trunk gradient (dark gold to amber)
    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, *GOLD_PRIMARY)
    pat.add_color_stop_rgb(0.5, *GOLD_DARK)
    pat.add_color_stop_rgb(1, 0.5, 0.35, 0.05)
    taper = trunk_w * 0.12
    ctx.move_to(trunk_x + taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w - taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w, trunk_y + trunk_h)
    ctx.line_to(trunk_x, trunk_y + trunk_h)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, GOLD_DARK, 6)

    # Resin drip details on trunk
    for i in range(4):
        drip_x = trunk_x + random.uniform(5, trunk_w - 5)
        drip_y = trunk_y + random.uniform(40, trunk_h - 30)
        drip_h = random.uniform(8, 20)
        ctx.set_line_width(2.5)
        set_color(ctx, GOLD_BRIGHT, 0.7)
        ctx.move_to(drip_x, drip_y)
        ctx.line_to(drip_x + random.uniform(-2, 2), drip_y + drip_h)
        ctx.stroke()
        # Drip blob at bottom
        draw_circle(ctx, drip_x, drip_y + drip_h, 2.5, GOLD_BRIGHT, 0.8)

    # ── Canopy: bright gold leaf blobs ──
    canopy_cy = trunk_y - 15
    blobs = [
        (cx, canopy_cy, 60),
        (cx - 45, canopy_cy + 10, 45),
        (cx + 45, canopy_cy + 10, 45),
        (cx - 22, canopy_cy - 35, 42),
        (cx + 22, canopy_cy - 35, 42),
        (cx, canopy_cy - 50, 38),
    ]

    # Golden glow behind canopy
    glow2 = cairo.RadialGradient(cx, canopy_cy, 15, cx, canopy_cy, 95)
    glow2.add_color_stop_rgba(0, *GOLD_BRIGHT, 0.35)
    glow2.add_color_stop_rgba(1, *GOLD_DARK, 0.0)
    ctx.arc(cx, canopy_cy, 110, 0, 2 * math.pi)
    ctx.set_source(glow2)
    ctx.fill()

    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, GOLD_PRIMARY, GOLD_DARK)
    # Lighter inner highlights
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx - 4, by - 4, br * 0.4,
                           GOLD_BRIGHT, GOLD_PRIMARY, 0.6, 0.0)

    # Metallic sparkle highlights
    for _ in range(20):
        dx = cx + random.gauss(0, 42)
        dy = canopy_cy + random.gauss(0, 38)
        dr = random.uniform(1.5, 3.5)
        draw_circle(ctx, dx, dy, dr, GOLD_METAL, random.uniform(0.5, 0.9))
    # White-gold specular highlights
    for _ in range(10):
        dx = cx + random.gauss(0, 50)
        dy = canopy_cy + random.gauss(0, 45)
        draw_circle(ctx, dx, dy, random.uniform(2, 4), GOLD_SPEC, random.uniform(0.3, 0.7))

    save_surface(surface, "tree_golden_tree_front.png")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Generating environment textures to {OUTPUT_DIR}/\n")

    generators = [
        ("Oak tree", generate_oak),
        ("Pine tree", generate_pine),
        ("Dead tree", generate_dead),
        ("Magic tree", generate_magic),
        ("Palm tree", generate_palm),
        ("Cactus", generate_cactus),
        ("Swamp tree", generate_swamp),
        ("Frost pine", generate_frost_pine),
        ("Crystal tree", generate_crystal_tree),
        ("Ember tree", generate_ember_tree),
        ("Dark oak", generate_dark_oak),
        ("Willow tree", generate_willow),
        ("Birch tree", generate_birch),
        ("Baobab tree", generate_baobab),
        ("Cherry blossom", generate_cherry_blossom),
        ("Giant mushroom", generate_mushroom_giant),
        ("Golden tree", generate_golden_tree),
        ("Bush", generate_bush),
        ("Rock", generate_rock),
        ("Grass", generate_grass),
        ("Fern", generate_fern),
        ("Blue flower", generate_flower_blue),
        ("Gold flower", generate_flower_gold),
        ("Tall grass", generate_tall_grass),
        ("Cattail", generate_cattail),
        ("Small mushroom", generate_mushroom_small),
        ("Crystal cluster", generate_crystal_cluster),
        ("Log", generate_log),
        ("Stump", generate_stump),
        ("Mossy rock", generate_rock_mossy),
        ("Crystal rock", generate_rock_crystal),
        ("Boulder", generate_boulder),
        ("Pinkberry bush", generate_pinkberry_bush),
        ("Rootbeer plant", generate_rootbeer_plant),
        ("Shadow mushroom", generate_shadow_mushroom),
        ("Nightshade bush", generate_nightshade_bush),
        ("Truffle spot", generate_truffle_spot),
        ("Bog root plant", generate_bog_root_plant),
        ("Marsh herb plant", generate_marsh_herb_plant),
        ("Lotus plant", generate_lotus_plant),
        ("Frost berry bush", generate_frost_berry_bush),
        ("Alpine herb plant", generate_alpine_herb_plant),
        ("Sage plant", generate_sage_plant),
        ("Mana fruit tree", generate_mana_fruit_tree),
        ("Arcane herb plant", generate_arcane_herb_plant),
        ("Ember pepper plant", generate_ember_pepper_plant),
        ("Brimstone plant", generate_brimstone_plant),
    ]

    for name, gen in generators:
        print(f"Generating {name}...")
        gen()

    print(f"\nDone! Generated {len(generators)} textures.")


if __name__ == "__main__":
    main()
