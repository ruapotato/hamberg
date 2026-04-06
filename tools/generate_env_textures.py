#!/usr/bin/env python3
"""
Generate vector-art environment sprites (trees, bushes, rocks, grass) using pycairo.
Outputs PNGs to assets/textures/environment/ for the game's texture override system.

Color palette:
  Primary: #0034ff (deep blue) shades
  Secondary: #ffca00 (metallic gold) shades
  Trees use natural greens/browns with blue/gold as accents.

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

# ── Palette — #0034ff blue + #ffca00 metallic gold ──────────────────────────
# Foliage: blue-shifted greens (natural but leaning into the blue palette)
GREEN_DARK   = (0.10, 0.30, 0.22)   # Blue-tinted dark green
GREEN_MED    = (0.15, 0.45, 0.30)   # Blue-green
GREEN_LIGHT  = (0.25, 0.58, 0.40)   # Lighter blue-green
GREEN_BRIGHT = (0.35, 0.70, 0.45)   # Bright with blue undertone
GREEN_YELLOW = (0.50, 0.72, 0.35)   # Gold-green transition

# Trunks: gold-shifted browns (warm, leaning into metallic gold)
BROWN_DARK   = (0.30, 0.20, 0.05)   # Dark gold-brown
BROWN_MED    = (0.48, 0.32, 0.10)   # Rich gold-brown
BROWN_LIGHT  = (0.62, 0.45, 0.18)   # Light gold-brown
BROWN_BARK   = (0.35, 0.22, 0.08)   # Warm bark

# Primary palette
BLUE_PRIMARY = (0.0, 0.204, 1.0)    # #0034ff
GOLD_PRIMARY = (1.0, 0.792, 0.0)    # #ffca00
BLUE_DARK    = (0.0, 0.1, 0.5)
GOLD_DARK    = (0.6, 0.47, 0.0)
BLUE_LIGHT   = (0.45, 0.55, 1.0)
GOLD_LIGHT   = (1.0, 0.90, 0.5)
GOLD_METAL   = (1.0, 0.95, 0.7)     # Metallic highlight
GOLD_SPEC    = (1.0, 1.0, 0.85)     # Specular white-gold

# Misc
WHITE  = (1.0, 1.0, 1.0)
SNOW   = (0.90, 0.93, 1.0)          # Blue-tinted snow
GRAY_LIGHT = (0.68, 0.68, 0.72)     # Blue-neutral gray
GRAY_MED   = (0.46, 0.45, 0.50)     # Blue-neutral mid
GRAY_DARK  = (0.28, 0.27, 0.32)     # Blue-neutral dark


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
        draw_circle(ctx, bx + 6, by + 6, br, (0.05, 0.12, 0.03), 0.35)
    # Main canopy with radial gradients
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, GREEN_LIGHT, GREEN_DARK)
    # Highlight layer (upper-left blobs brighter)
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx - 8, by - 8, br * 0.5,
                           GREEN_BRIGHT, GREEN_LIGHT, 0.6, 0.0)
    # Leaf detail dots
    for _ in range(40):
        dx = cx + random.gauss(0, 50)
        dy = canopy_cy + random.gauss(0, 45)
        dr = random.uniform(3, 8)
        c = random.choice([GREEN_BRIGHT, GREEN_YELLOW, GREEN_MED])
        draw_circle(ctx, dx, dy, dr, c, random.uniform(0.3, 0.6))

    # Gold accent: tiny sparkle dots
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
        set_color(ctx, (0.03, 0.10, 0.02), 0.3)
        ctx.fill()
        # Triangle with gradient
        pat = cairo.LinearGradient(cx, ly - lh, cx, ly)
        pat.add_color_stop_rgb(0, *GREEN_LIGHT)
        pat.add_color_stop_rgb(0.4, *GREEN_MED)
        pat.add_color_stop_rgb(1, *GREEN_DARK)
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
        set_color(ctx, GREEN_BRIGHT, 0.4)
        ctx.stroke()
        ctx.move_to(cx, ly - lh)
        ctx.line_to(cx - lw, ly)
        set_color(ctx, GREEN_BRIGHT, 0.3)
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

    # Draw thick trunk with curve
    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, 0.30, 0.18, 0.10)
    pat.add_color_stop_rgb(1, 0.18, 0.10, 0.05)

    ctx.move_to(cx - 18, trunk_bot)
    ctx.curve_to(cx - 22, trunk_bot - 100, cx + 15, trunk_bot - 180, cx - 5, trunk_top)
    ctx.line_to(cx + 12, trunk_top + 5)
    ctx.curve_to(cx + 25, trunk_bot - 170, cx - 10, trunk_bot - 90, cx + 18, trunk_bot)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    # Bark cracks
    ctx.set_line_width(1.2)
    for _ in range(8):
        by = random.uniform(trunk_top + 30, trunk_bot - 30)
        bx = cx + random.uniform(-12, 12)
        ctx.move_to(bx, by)
        ctx.line_to(bx + random.uniform(-5, 5), by + random.uniform(8, 20))
        set_color(ctx, (0.10, 0.05, 0.02), 0.5)
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
        set_color(ctx, (0.22, 0.13, 0.06))
        ctx.stroke()
        # Sub-branch
        ctx.set_line_width(2.5)
        ctx.move_to(x1, y1)
        ctx.curve_to(x1 + random.uniform(-20, 20), y1 - 20,
                     x1 + random.uniform(-30, 30), y1 - 35,
                     x1 + random.uniform(-25, 25), y1 - 45)
        set_color(ctx, (0.20, 0.12, 0.05))
        ctx.stroke()

    # Root gnarls at base
    for side in [-1, 1]:
        ctx.set_line_width(6)
        ctx.move_to(cx + side * 16, trunk_bot)
        ctx.curve_to(cx + side * 35, trunk_bot + 5,
                     cx + side * 45, trunk_bot - 5,
                     cx + side * 50, trunk_bot + 2)
        set_color(ctx, (0.18, 0.10, 0.05))
        ctx.stroke()

    save_surface(surface, "tree_dead_front.png")


def generate_magic(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Purple-blue trunk with glow ──
    trunk_w, trunk_h = 30, 190
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 20

    # Glow halo behind trunk
    glow = cairo.RadialGradient(cx, trunk_y + trunk_h / 2, trunk_w / 2,
                                cx, trunk_y + trunk_h / 2, trunk_w * 2)
    glow.add_color_stop_rgba(0, 0.4, 0.2, 0.8, 0.25)
    glow.add_color_stop_rgba(1, 0.2, 0.1, 0.5, 0.0)
    ctx.rectangle(cx - trunk_w * 2, trunk_y - 20, trunk_w * 4, trunk_h + 40)
    ctx.set_source(glow)
    ctx.fill()

    # Trunk
    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, 0.35, 0.15, 0.55)
    pat.add_color_stop_rgb(1, 0.20, 0.08, 0.35)
    taper = trunk_w * 0.1
    ctx.move_to(trunk_x + taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w - taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w, trunk_y + trunk_h)
    ctx.line_to(trunk_x, trunk_y + trunk_h)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, (0.15, 0.05, 0.25), 5)

    # ── Canopy: blue-purple circles ──
    canopy_cy = trunk_y - 20
    blobs = [
        (cx, canopy_cy, 65),
        (cx - 48, canopy_cy + 12, 48),
        (cx + 48, canopy_cy + 12, 48),
        (cx - 25, canopy_cy - 38, 45),
        (cx + 25, canopy_cy - 38, 45),
        (cx, canopy_cy - 55, 40),
    ]
    # Glow behind canopy
    glow2 = cairo.RadialGradient(cx, canopy_cy, 20, cx, canopy_cy, 100)
    glow2.add_color_stop_rgba(0, 0.3, 0.15, 0.7, 0.3)
    glow2.add_color_stop_rgba(1, 0.15, 0.05, 0.4, 0.0)
    ctx.arc(cx, canopy_cy, 110, 0, 2 * math.pi)
    ctx.set_source(glow2)
    ctx.fill()

    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br,
                           (0.35, 0.25, 0.75), (0.15, 0.08, 0.45))
    # Lighter inner glow
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx - 5, by - 5, br * 0.4,
                           (0.55, 0.40, 0.90), (0.35, 0.20, 0.70), 0.5, 0.0)

    # Sparkle dots
    for _ in range(25):
        dx = cx + random.gauss(0, 45)
        dy = canopy_cy + random.gauss(0, 40)
        dr = random.uniform(1.5, 3.5)
        draw_circle(ctx, dx, dy, dr, WHITE, random.uniform(0.5, 0.95))
    # Golden glow particles
    for _ in range(8):
        dx = cx + random.gauss(0, 55)
        dy = canopy_cy + random.gauss(0, 50)
        draw_circle(ctx, dx, dy, random.uniform(2, 4), GOLD_PRIMARY, random.uniform(0.3, 0.7))

    save_surface(surface, "tree_magic_front.png")


def generate_palm(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Curved trunk ──
    trunk_bot = cy_base - 20
    trunk_top = cy_base - 340

    # S-curve trunk
    ctx.set_line_width(24)
    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, 0.55, 0.40, 0.22)
    pat.add_color_stop_rgb(1, 0.38, 0.25, 0.12)

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
        pat.add_color_stop_rgb(0, *GREEN_MED)
        pat.add_color_stop_rgb(0.5, *GREEN_LIGHT)
        pat.add_color_stop_rgb(1, *GREEN_MED)
        ctx.set_source(pat)
        ctx.fill()

        # Spine line (center vein)
        ctx.set_line_width(1.8)
        ctx.move_to(top_x, top_y)
        ctx.curve_to(ctrl_x, ctrl_y, end_x, end_y - 15, end_x, end_y)
        set_color(ctx, GREEN_DARK, 0.6)
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
                set_color(ctx, GREEN_DARK, 0.2)
                ctx.stroke()

    # Coconuts
    for dx, dy in [(-8, 8), (5, 10), (0, 15)]:
        draw_circle(ctx, top_x + dx, top_y + dy, 6, BROWN_MED)
        draw_circle(ctx, top_x + dx - 1, top_y + dy - 1, 2, BROWN_LIGHT, 0.5)

    save_surface(surface, "tree_palm_front.png")


def generate_cactus(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    body_bot = cy_base - 25
    body_top = cy_base - 310
    body_w = 45

    # ── Main body (rounded rectangle / tall ellipse) ──
    pat = cairo.LinearGradient(cx - body_w, body_top, cx + body_w, body_bot)
    pat.add_color_stop_rgb(0, 0.25, 0.55, 0.20)
    pat.add_color_stop_rgb(0.5, 0.18, 0.48, 0.15)
    pat.add_color_stop_rgb(1, 0.12, 0.38, 0.10)

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
        set_color(ctx, (0.10, 0.32, 0.08), 0.35)
        ctx.stroke()

    # ── Left arm ──
    arm_y = body_bot - 160
    ctx.set_line_width(28)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.move_to(cx - body_w + 5, arm_y)
    ctx.curve_to(cx - body_w - 40, arm_y,
                 cx - body_w - 45, arm_y - 60,
                 cx - body_w - 40, arm_y - 80)
    set_color(ctx, (0.20, 0.50, 0.17))
    ctx.stroke()
    # Highlight
    ctx.set_line_width(8)
    ctx.move_to(cx - body_w + 2, arm_y)
    ctx.curve_to(cx - body_w - 38, arm_y,
                 cx - body_w - 43, arm_y - 55,
                 cx - body_w - 38, arm_y - 75)
    set_color(ctx, (0.30, 0.58, 0.25), 0.4)
    ctx.stroke()

    # ── Right arm ──
    arm_y2 = body_bot - 120
    ctx.set_line_width(24)
    ctx.move_to(cx + body_w - 5, arm_y2)
    ctx.curve_to(cx + body_w + 35, arm_y2,
                 cx + body_w + 40, arm_y2 - 50,
                 cx + body_w + 35, arm_y2 - 70)
    set_color(ctx, (0.20, 0.50, 0.17))
    ctx.stroke()
    ctx.set_line_width(7)
    ctx.move_to(cx + body_w - 3, arm_y2)
    ctx.curve_to(cx + body_w + 33, arm_y2,
                 cx + body_w + 38, arm_y2 - 45,
                 cx + body_w + 33, arm_y2 - 65)
    set_color(ctx, (0.30, 0.58, 0.25), 0.4)
    ctx.stroke()

    # Spine dots
    for _ in range(30):
        sx = cx + random.uniform(-body_w + 5, body_w - 5)
        sy = random.uniform(body_top + body_w + 10, body_bot - 10)
        draw_circle(ctx, sx, sy, 1.2, (0.85, 0.82, 0.60), 0.6)

    # Flower on top
    flower_cx, flower_cy = cx, body_top + body_w - 8
    petals = 6
    for i in range(petals):
        angle = i * 2 * math.pi / petals
        px = flower_cx + math.cos(angle) * 10
        py = flower_cy + math.sin(angle) * 10
        draw_circle(ctx, px, py, 7, (0.95, 0.45, 0.55), 0.85)
    draw_circle(ctx, flower_cx, flower_cy, 5, (1.0, 0.85, 0.20))

    save_surface(surface, "tree_cactus_front.png")


def generate_swamp(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Twisted trunk ──
    trunk_bot = cy_base - 20
    trunk_top = cy_base - 280

    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, 0.28, 0.22, 0.12)
    pat.add_color_stop_rgb(1, 0.15, 0.12, 0.06)

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
            set_color(ctx, (0.18, 0.14, 0.07))
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
                           (0.22, 0.38, 0.15), (0.12, 0.25, 0.08), 0.85, 0.7)

    # Hanging moss
    ctx.set_line_width(1.2)
    for bx, by, br in blobs:
        for _ in range(random.randint(4, 8)):
            mx = bx + random.uniform(-br * 0.7, br * 0.7)
            my = by + br * 0.5
            moss_len = random.uniform(20, 50)
            ctx.move_to(mx, my)
            ctx.line_to(mx + random.uniform(-5, 5), my + moss_len)
            set_color(ctx, (0.30, 0.45, 0.20), random.uniform(0.4, 0.7))
            ctx.stroke()

    save_surface(surface, "tree_swamp_front.png")


def generate_frost_pine(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Ice-blue trunk ──
    trunk_w, trunk_h = 20, 170
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 15
    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, 0.55, 0.65, 0.75)
    pat.add_color_stop_rgb(1, 0.35, 0.42, 0.55)
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
        # Main triangle (blue-green)
        pat = cairo.LinearGradient(cx, ly - lh, cx, ly)
        pat.add_color_stop_rgb(0, 0.25, 0.50, 0.45)
        pat.add_color_stop_rgb(1, 0.12, 0.32, 0.28)
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
    pat.add_color_stop_rgb(0, 0.70, 0.75, 0.90)
    pat.add_color_stop_rgb(0.5, 0.50, 0.55, 0.80)
    pat.add_color_stop_rgb(1, 0.35, 0.38, 0.65)
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
        # Iridescent gradient
        pat = cairo.LinearGradient(tip_x - hw, tip_y, tip_x + hw, base_y)
        pat.add_color_stop_rgba(0, 0.55, 0.35, 0.85, 0.85)   # purple
        pat.add_color_stop_rgba(0.4, 0.35, 0.50, 0.95, 0.80)  # blue
        pat.add_color_stop_rgba(0.7, 0.80, 0.45, 0.70, 0.75)  # pink
        pat.add_color_stop_rgba(1, 0.40, 0.60, 0.90, 0.70)   # lighter blue

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

    # Bright sparkle highlights
    for _ in range(15):
        sx = cx + random.gauss(0, 40)
        sy = trunk_top - 50 + random.gauss(0, 50)
        sr = random.uniform(1.5, 4)
        draw_circle(ctx, sx, sy, sr, WHITE, random.uniform(0.6, 1.0))

    save_surface(surface, "tree_crystal_tree_front.png")


def generate_ember_tree(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    trunk_bot = cy_base - 20
    trunk_top = cy_base - 280

    # ── Charred trunk ──
    pat = cairo.LinearGradient(cx, trunk_top, cx, trunk_bot)
    pat.add_color_stop_rgb(0, 0.12, 0.08, 0.06)
    pat.add_color_stop_rgb(1, 0.08, 0.05, 0.03)

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
        set_color(ctx, (1.0, 0.5, 0.1), random.uniform(0.5, 0.9))
        ctx.stroke()
    # Glow around cracks
    ctx.set_line_width(6)
    for _ in range(5):
        cy = random.uniform(trunk_top + 30, trunk_bot - 30)
        cxx = cx + random.uniform(-trunk_w + 8, trunk_w - 8)
        ctx.move_to(cxx, cy)
        ctx.line_to(cxx + random.uniform(-5, 5), cy + random.uniform(10, 25))
        set_color(ctx, (1.0, 0.3, 0.0), 0.15)
        ctx.stroke()

    # ── Flame-colored canopy ──
    canopy_cy = trunk_top + 10
    blobs = [
        (cx, canopy_cy - 30, 58),
        (cx - 42, canopy_cy, 42),
        (cx + 42, canopy_cy, 42),
        (cx - 20, canopy_cy - 55, 38),
        (cx + 20, canopy_cy - 55, 38),
        (cx, canopy_cy - 75, 35),
    ]
    # Glow behind
    glow = cairo.RadialGradient(cx, canopy_cy - 30, 20, cx, canopy_cy - 30, 100)
    glow.add_color_stop_rgba(0, 1.0, 0.4, 0.0, 0.3)
    glow.add_color_stop_rgba(1, 0.8, 0.2, 0.0, 0.0)
    ctx.arc(cx, canopy_cy - 30, 110, 0, 2 * math.pi)
    ctx.set_source(glow)
    ctx.fill()

    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br,
                           (1.0, 0.65, 0.15), (0.8, 0.20, 0.05))
    # Bright inner
    for bx, by, br in blobs[:3]:
        draw_radial_circle(ctx, bx, by - 5, br * 0.4,
                           (1.0, 0.90, 0.40), (1.0, 0.60, 0.10), 0.6, 0.0)

    # Ember particles
    for _ in range(20):
        ex = cx + random.gauss(0, 55)
        ey = canopy_cy + random.gauss(-30, 50)
        er = random.uniform(1.5, 3.5)
        c = random.choice([(1.0, 0.9, 0.3), (1.0, 0.6, 0.1), (1.0, 0.4, 0.05)])
        draw_circle(ctx, ex, ey, er, c, random.uniform(0.6, 1.0))

    save_surface(surface, "tree_ember_tree_front.png")


def generate_dark_oak(w=256, h=512):
    surface, ctx = make_surface(w, h)
    cx, cy_base = w / 2, h

    # ── Very thick dark trunk ──
    trunk_w, trunk_h = 55, 210
    trunk_x = cx - trunk_w / 2
    trunk_y = cy_base - trunk_h - 20
    pat = cairo.LinearGradient(trunk_x, trunk_y, trunk_x, trunk_y + trunk_h)
    pat.add_color_stop_rgb(0, 0.18, 0.12, 0.08)
    pat.add_color_stop_rgb(1, 0.10, 0.06, 0.03)
    taper = trunk_w * 0.08
    ctx.move_to(trunk_x + taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w - taper, trunk_y)
    ctx.line_to(trunk_x + trunk_w + 5, trunk_y + trunk_h)
    ctx.line_to(trunk_x - 5, trunk_y + trunk_h)
    ctx.close_path()
    ctx.set_source(pat)
    ctx.fill()

    draw_bark_texture(ctx, trunk_x, trunk_y, trunk_w, trunk_h, (0.06, 0.03, 0.01), 20)
    draw_wood_grain(ctx, trunk_x, trunk_y, trunk_w, trunk_h, (0.06, 0.03, 0.01), 8)

    # Moss/lichen patches
    for _ in range(5):
        mx = trunk_x + random.uniform(5, trunk_w - 5)
        my = trunk_y + random.uniform(20, trunk_h - 20)
        mr = random.uniform(6, 12)
        draw_circle(ctx, mx, my, mr, (0.20, 0.35, 0.15), 0.5)

    # Root buttresses
    for side in [-1, 1]:
        ctx.move_to(cx + side * (trunk_w / 2 + 3), cy_base - 20)
        ctx.curve_to(cx + side * (trunk_w / 2 + 30), cy_base - 8,
                     cx + side * (trunk_w / 2 + 40), cy_base,
                     cx + side * (trunk_w / 2 + 25), cy_base + 5)
        ctx.line_to(cx + side * trunk_w / 2, cy_base - 20)
        ctx.close_path()
        set_color(ctx, (0.12, 0.07, 0.03))
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
        draw_radial_circle(ctx, bx, by, br,
                           (0.10, 0.20, 0.06), (0.04, 0.10, 0.02))
    # Extra dark overlay
    for bx, by, br in blobs:
        draw_circle(ctx, bx + 3, by + 3, br * 0.6, (0.02, 0.05, 0.01), 0.3)

    # Tiny glowing eyes (creepy)
    eye_positions = [
        (cx - 30, canopy_cy + 5),
        (cx + 45, canopy_cy - 10),
        (cx - 10, canopy_cy - 35),
    ]
    for ex, ey in eye_positions:
        for dx in [-4, 4]:
            # Glow
            draw_circle(ctx, ex + dx, ey, 4, (0.8, 1.0, 0.2), 0.15)
            # Eye
            draw_circle(ctx, ex + dx, ey, 2, (0.9, 1.0, 0.3), 0.8)
            draw_circle(ctx, ex + dx, ey, 0.8, (1.0, 1.0, 0.5), 1.0)

    save_surface(surface, "tree_dark_oak_front.png")


# ── Non-tree environment ────────────────────────────────────────────────────

def generate_bush(w=128, h=128):
    surface, ctx = make_surface(w, h)
    cx, cy = w / 2, h * 0.6

    # Small brown stems
    ctx.set_line_width(3)
    for angle in [-0.5, -0.2, 0.1, 0.4]:
        ctx.move_to(cx + angle * 15, h - 10)
        ctx.line_to(cx + angle * 25, cy + 5)
        set_color(ctx, BROWN_MED)
        ctx.stroke()

    # Green leaf clusters
    blobs = [
        (cx, cy, 30),
        (cx - 28, cy + 8, 22),
        (cx + 28, cy + 8, 22),
        (cx - 15, cy - 15, 20),
        (cx + 15, cy - 15, 20),
        (cx, cy + 15, 25),
    ]
    for bx, by, br in blobs:
        draw_radial_circle(ctx, bx, by, br, GREEN_LIGHT, GREEN_DARK)

    # Highlight
    for bx, by, br in blobs[:2]:
        draw_radial_circle(ctx, bx - 3, by - 3, br * 0.4,
                           GREEN_BRIGHT, GREEN_LIGHT, 0.5, 0.0)

    # Small flowers/berries
    for _ in range(6):
        fx = cx + random.uniform(-30, 30)
        fy = cy + random.uniform(-15, 15)
        c = random.choice([(0.9, 0.2, 0.25), (0.95, 0.85, 0.2), GOLD_PRIMARY])
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

    # Moss patch
    draw_circle(ctx, cx + 12, cy + 10, 8, GREEN_DARK, 0.45)
    draw_circle(ctx, cx + 15, cy + 8, 5, GREEN_MED, 0.35)

    save_surface(surface, "rock.png")


def generate_grass(w=64, h=128):
    surface, ctx = make_surface(w, h)
    cx = w / 2

    # Several grass blades
    blades = [
        (cx - 18, 0.9, -0.3),
        (cx - 10, 1.0, -0.15),
        (cx - 3, 1.05, 0.05),
        (cx + 5, 0.95, 0.2),
        (cx + 13, 0.85, 0.1),
        (cx + 20, 0.75, -0.1),
        (cx - 14, 0.7, 0.15),
        (cx + 8, 0.80, -0.2),
    ]

    for bx, height_frac, lean in blades:
        blade_h = h * height_frac * 0.75
        base_y = h - 5
        tip_y = base_y - blade_h
        tip_x = bx + lean * 30

        blade_w = random.uniform(3, 5)

        # Gradient: dark green base to yellow-green tip
        pat = cairo.LinearGradient(bx, base_y, tip_x, tip_y)
        pat.add_color_stop_rgb(0, *GREEN_DARK)
        pat.add_color_stop_rgb(0.6, *GREEN_MED)
        pat.add_color_stop_rgb(1, *GREEN_YELLOW)

        # Blade shape: tapered with slight curve
        ctrl_x = bx + lean * 15
        ctrl_y = base_y - blade_h * 0.5

        ctx.move_to(bx - blade_w, base_y)
        ctx.curve_to(ctrl_x - blade_w * 0.5, ctrl_y,
                     tip_x - 1, tip_y + 10,
                     tip_x, tip_y)
        ctx.curve_to(tip_x + 1, tip_y + 10,
                     ctrl_x + blade_w * 0.5, ctrl_y,
                     bx + blade_w, base_y)
        ctx.close_path()
        ctx.set_source(pat)
        ctx.fill()

        # Subtle center line highlight
        ctx.set_line_width(0.8)
        ctx.move_to(bx, base_y)
        ctx.curve_to(ctrl_x, ctrl_y, tip_x, tip_y + 10, tip_x, tip_y)
        set_color(ctx, GREEN_BRIGHT, 0.25)
        ctx.stroke()

    save_surface(surface, "grass.png")


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
        ("Bush", generate_bush),
        ("Rock", generate_rock),
        ("Grass", generate_grass),
    ]

    for name, gen in generators:
        print(f"Generating {name}...")
        gen()

    print(f"\nDone! Generated {len(generators)} textures.")


if __name__ == "__main__":
    main()
