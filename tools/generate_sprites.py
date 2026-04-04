#!/usr/bin/env python3
"""Generate multi-angle character sprite sheets using Cairo.

Renders each character at 36 angles (every 10 degrees) into individual PNGs
and a combined sprite sheet. Uses the same drawing approach as The-Mount:
facing = cos(angle), turn_side = sin(angle).

Angle 0 = front (facing camera), 90 = left side, 180 = back, 270 = right side.

Output structure:
    assets/sprites/characters/{name}/
        angle_000.png  (front)
        angle_010.png
        ...
        angle_350.png
        sheet.png      (all angles in a 6-column grid)

Usage:
    python3 tools/generate_sprites.py
    python3 tools/generate_sprites.py --characters mage deer
    python3 tools/generate_sprites.py --angles 72 --size 128x192
"""

import argparse
import math
from pathlib import Path

import cairo

SCRIPT_DIR = Path(__file__).parent
OUT_BASE = SCRIPT_DIR.parent / "assets" / "sprites" / "characters"


# ── Colors ─────────────────────────────────────────────────────────

OUTLINE_GREEN = (0.20, 0.86, 0.31)


# ── Drawing helpers (from The-Mount base.py) ───────────────────────

def set_color(ctx, r, g, b, a=1.0):
    if a < 1.0:
        ctx.set_source_rgba(r, g, b, a)
    else:
        ctx.set_source_rgb(r, g, b)


def fill_circle(ctx, x, y, radius, color):
    ctx.arc(x, y, radius, 0, math.tau)
    set_color(ctx, *color)
    ctx.fill()


def stroke_circle(ctx, x, y, radius, color, width=2):
    ctx.arc(x, y, radius, 0, math.tau)
    set_color(ctx, *color)
    ctx.set_line_width(width)
    ctx.stroke()


def fill_ellipse(ctx, x, y, rx, ry, color):
    if rx < 0.5 or ry < 0.5:
        return
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(rx, ry)
    ctx.arc(0, 0, 1, 0, math.tau)
    ctx.restore()
    set_color(ctx, *color)
    ctx.fill()


def stroke_ellipse(ctx, x, y, rx, ry, color, width=2):
    if rx < 0.5 or ry < 0.5:
        return
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(rx, ry)
    ctx.arc(0, 0, 1, 0, math.tau)
    ctx.restore()
    set_color(ctx, *color)
    ctx.set_line_width(width)
    ctx.stroke()


def draw_line(ctx, x0, y0, x1, y1, color, width=2):
    ctx.move_to(x0, y0)
    ctx.line_to(x1, y1)
    set_color(ctx, *color)
    ctx.set_line_width(width)
    ctx.stroke()


def draw_limb(ctx, x0, y0, x1, y1, thickness, color, outline_color=OUTLINE_GREEN):
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    # Outline
    ctx.move_to(x0, y0)
    ctx.line_to(x1, y1)
    set_color(ctx, *outline_color)
    ctx.set_line_width(thickness + 3)
    ctx.stroke()
    # Fill
    ctx.move_to(x0, y0)
    ctx.line_to(x1, y1)
    set_color(ctx, *color)
    ctx.set_line_width(thickness)
    ctx.stroke()


def draw_body_oval(ctx, cx, cy, width, height, color, outline_color=OUTLINE_GREEN):
    stroke_ellipse(ctx, cx, cy, width + 1.5, height + 1.5, outline_color, 3)
    fill_ellipse(ctx, cx, cy, width, height, color)


def draw_head(ctx, cx, cy, radius, skin_color, outline_color=OUTLINE_GREEN):
    stroke_circle(ctx, cx, cy, radius + 1.5, outline_color, 3)
    fill_circle(ctx, cx, cy, radius, skin_color)


def draw_3d_oval(ctx, cx, cy, rx, ry, base_color, turn_side=0.0, facing=1.0,
                 outline_color=OUTLINE_GREEN, highlight_color=None, shadow_color=None):
    if highlight_color is None:
        highlight_color = tuple(min(1.0, c + 0.15) for c in base_color[:3])
    if shadow_color is None:
        shadow_color = tuple(max(0.0, c - 0.12) for c in base_color[:3])

    stroke_ellipse(ctx, cx, cy, rx + 1.5, ry + 1.5, outline_color, 2.5)
    fill_ellipse(ctx, cx, cy, rx, ry, base_color)

    if rx > 3:
        shift = turn_side * rx * 0.3
        shadow_rx = rx * 0.6
        shadow_shift = -turn_side * rx * 0.25
        fill_ellipse(ctx, cx + shadow_shift, cy, shadow_rx, ry * 0.85,
                     (*shadow_color, 0.35))
        hi_rx = rx * 0.5
        fill_ellipse(ctx, cx + shift, cy - ry * 0.1, hi_rx, ry * 0.7,
                     (*highlight_color, 0.3))


def draw_eyes(ctx, cx, cy, head_radius, eye_color, facing=1.0,
              eye_scale=1.0, pupil_color=(0.1, 0.1, 0.15), turn_side=0.0):
    eye_r = head_radius * 0.2 * eye_scale
    pupil_r = eye_r * 0.55
    base_spread = head_radius * 0.35

    if facing < 0.1:
        return

    face_amount = facing
    sphere_shift = turn_side * head_radius * 0.5
    spread = base_spread * face_amount
    eye_y = cy - head_radius * 0.1

    for side in [-1, 1]:
        ex = cx + side * spread + sphere_shift
        eye_rx = eye_r * (0.3 + face_amount * 0.7)
        eye_ry = eye_r

        fill_ellipse(ctx, ex, eye_y, eye_rx, eye_ry, (1.0, 1.0, 1.0))
        pupil_shift = turn_side * eye_rx * 0.15
        fill_ellipse(ctx, ex + pupil_shift, eye_y,
                     pupil_r * (0.5 + face_amount * 0.5), pupil_r, pupil_color)
        fill_circle(ctx, ex - eye_rx * 0.25, eye_y - eye_r * 0.25,
                    eye_r * 0.2, (1.0, 1.0, 1.0, 0.7))


# ── Character color palettes ──────────────────────────────────────

CHAR_COLORS = {
    "mage": {
        "skin": (0.85, 0.78, 0.70),
        "robe": (0.45, 0.35, 0.75),
        "robe_dark": (0.30, 0.22, 0.55),
        "hat": (0.35, 0.25, 0.65),
        "staff": (0.55, 0.40, 0.25),
        "eye": (0.3, 0.4, 0.9),
        "hair": (0.5, 0.45, 0.55),
    },
    "warrior": {
        "skin": (0.82, 0.68, 0.55),
        "armor": (0.55, 0.50, 0.45),
        "armor_dark": (0.40, 0.36, 0.32),
        "eye": (0.35, 0.55, 0.3),
        "hair": (0.45, 0.30, 0.15),
        "pants": (0.35, 0.28, 0.22),
    },
    "zombie_walker": {
        "skin": (0.45, 0.58, 0.38),
        "clothes": (0.35, 0.30, 0.28),
        "clothes_dark": (0.25, 0.20, 0.18),
        "eye": (0.8, 0.75, 0.2),
        "hair": (0.3, 0.28, 0.25),
    },
    "zombie_runner": {
        "skin": (0.55, 0.42, 0.40),
        "clothes": (0.50, 0.25, 0.22),
        "clothes_dark": (0.38, 0.18, 0.15),
        "eye": (0.9, 0.2, 0.15),
        "hair": (0.25, 0.18, 0.15),
    },
    "zombie_brute": {
        "skin": (0.50, 0.55, 0.42),
        "clothes": (0.40, 0.38, 0.35),
        "clothes_dark": (0.28, 0.26, 0.24),
        "eye": (0.7, 0.65, 0.15),
        "hair": (0.22, 0.20, 0.18),
    },
    "skeleton": {
        "bone": (0.88, 0.82, 0.72),
        "bone_dark": (0.70, 0.64, 0.54),
        "eye": (0.1, 0.1, 0.1),
    },
    "deer": {
        "body": (0.65, 0.45, 0.28),
        "body_light": (0.78, 0.60, 0.42),
        "legs": (0.50, 0.35, 0.22),
        "antler": (0.55, 0.40, 0.25),
        "eye": (0.15, 0.12, 0.08),
    },
    "pig": {
        "body": (0.90, 0.72, 0.72),
        "body_dark": (0.78, 0.58, 0.58),
        "snout": (0.95, 0.65, 0.65),
        "legs": (0.80, 0.60, 0.60),
        "eye": (0.15, 0.12, 0.12),
    },
    "sheep": {
        "wool": (0.92, 0.90, 0.85),
        "wool_dark": (0.80, 0.78, 0.72),
        "face": (0.25, 0.22, 0.20),
        "legs": (0.20, 0.18, 0.16),
        "eye": (0.12, 0.10, 0.08),
    },
}


# ── Humanoid drawing functions ─────────────────────────────────────

def draw_mage(ctx, cx, cy, facing, turn_side):
    """Draw a mage with wizard hat, robe, and staff."""
    C = CHAR_COLORS["mage"]
    abs_f = abs(facing)
    fw = 0.35 + abs_f * 0.65  # width factor

    head_r = 22
    head_y = cy - 110
    neck_y = head_y + head_r + 4
    torso_y = neck_y + 10
    torso_h = 55
    hip_y = torso_y + torso_h
    torso_rx = 28 * fw
    torso_ry = torso_h * 0.5

    # Legs
    leg_len = 55
    leg_spread = 12 * fw
    for side in [-1, 1]:
        lx = cx + side * leg_spread
        draw_limb(ctx, lx, hip_y, lx + side * 4, hip_y + leg_len,
                  10 * fw, C["robe_dark"])
        # Feet
        foot_x = lx + side * 4
        foot_y = hip_y + leg_len
        fill_ellipse(ctx, foot_x + turn_side * 3, foot_y + 2, 8, 4, C["robe_dark"])
        stroke_ellipse(ctx, foot_x + turn_side * 3, foot_y + 2, 8, 4, OUTLINE_GREEN, 1.5)

    # Robe / torso
    draw_3d_oval(ctx, cx, torso_y + torso_ry, torso_rx, torso_ry,
                 C["robe"], turn_side=turn_side, facing=facing)

    # Robe skirt extension
    skirt_rx = torso_rx * 1.1
    skirt_ry = 20
    draw_3d_oval(ctx, cx, hip_y, skirt_rx, skirt_ry,
                 C["robe_dark"], turn_side=turn_side, facing=facing)

    # Arms
    shoulder_w = torso_rx * 0.85
    arm_len = 50
    for side in [-1, 1]:
        sx_arm = cx + side * shoulder_w + turn_side * 8
        sy_arm = torso_y + 10
        elbow_x = sx_arm + side * 12 * fw + turn_side * 5
        elbow_y = sy_arm + arm_len * 0.5
        hand_x = elbow_x + side * 5 * fw + turn_side * 3
        hand_y = elbow_y + arm_len * 0.4
        draw_limb(ctx, sx_arm, sy_arm, elbow_x, elbow_y, 8 * fw, C["robe"])
        draw_limb(ctx, elbow_x, elbow_y, hand_x, hand_y, 6 * fw, C["skin"])
        fill_circle(ctx, hand_x, hand_y, 4, C["skin"])
        stroke_circle(ctx, hand_x, hand_y, 4, OUTLINE_GREEN, 1.5)

    # Staff (right hand side)
    staff_x = cx + shoulder_w + turn_side * 15 + 8
    staff_top = head_y - 30
    staff_bot = hip_y + leg_len - 5
    draw_limb(ctx, staff_x, staff_top, staff_x + 2, staff_bot, 4, C["staff"])
    # Staff orb
    fill_circle(ctx, staff_x + 1, staff_top, 7, (0.6, 0.5, 0.95))
    stroke_circle(ctx, staff_x + 1, staff_top, 7, OUTLINE_GREEN, 2)
    fill_circle(ctx, staff_x - 1, staff_top - 2, 3, (0.8, 0.75, 1.0, 0.6))

    # Neck
    draw_limb(ctx, cx + turn_side * 3, neck_y, cx + turn_side * 2, torso_y,
              8 * fw, C["skin"])

    # Head
    draw_head(ctx, cx + turn_side * 5, head_y, head_r, C["skin"])

    # Wizard hat
    hat_cx = cx + turn_side * 5
    hat_base_y = head_y - head_r + 2
    hat_tip_y = head_y - head_r - 35
    hat_brim_hw = head_r + 8
    # Brim
    fill_ellipse(ctx, hat_cx, hat_base_y, hat_brim_hw * fw, 5, C["hat"])
    stroke_ellipse(ctx, hat_cx, hat_base_y, hat_brim_hw * fw, 5, OUTLINE_GREEN, 2)
    # Cone
    ctx.move_to(hat_cx - head_r * fw * 0.8, hat_base_y)
    ctx.line_to(hat_cx + turn_side * 8, hat_tip_y)
    ctx.line_to(hat_cx + head_r * fw * 0.8, hat_base_y)
    ctx.close_path()
    set_color(ctx, *C["hat"])
    ctx.fill_preserve()
    set_color(ctx, *OUTLINE_GREEN)
    ctx.set_line_width(2)
    ctx.stroke()

    # Face
    if facing > 0.1:
        draw_eyes(ctx, cx + turn_side * 5, head_y, head_r, C["eye"],
                  facing, eye_scale=1.0, turn_side=turn_side)
        # Beard
        beard_cx = cx + turn_side * head_r * 0.45 + turn_side * 5
        beard_y = head_y + head_r * 0.4
        beard_w = head_r * 0.3 * (0.3 + abs_f * 0.7)
        for i in range(3):
            by = beard_y + i * 6
            bw = beard_w * (1.0 - i * 0.2)
            draw_line(ctx, beard_cx - bw, by, beard_cx + bw, by + 4,
                      C["hair"], 2)


def draw_warrior(ctx, cx, cy, facing, turn_side):
    """Draw a warrior with armor."""
    C = CHAR_COLORS["warrior"]
    abs_f = abs(facing)
    fw = 0.35 + abs_f * 0.65

    head_r = 20
    head_y = cy - 105
    neck_y = head_y + head_r + 4
    torso_y = neck_y + 8
    torso_h = 50
    hip_y = torso_y + torso_h
    torso_rx = 32 * fw
    torso_ry = torso_h * 0.5

    # Legs
    leg_len = 60
    leg_spread = 14 * fw
    for side in [-1, 1]:
        lx = cx + side * leg_spread
        draw_limb(ctx, lx, hip_y, lx + side * 3, hip_y + leg_len,
                  12 * fw, C["pants"])
        foot_x = lx + side * 3
        foot_y = hip_y + leg_len
        fill_ellipse(ctx, foot_x + turn_side * 3, foot_y + 2, 9, 5, C["armor_dark"])
        stroke_ellipse(ctx, foot_x + turn_side * 3, foot_y + 2, 9, 5, OUTLINE_GREEN, 1.5)

    # Torso (armor)
    draw_3d_oval(ctx, cx, torso_y + torso_ry, torso_rx, torso_ry,
                 C["armor"], turn_side=turn_side, facing=facing)

    # Belt
    belt_y = hip_y - 5
    belt_rx = torso_rx * 0.95
    fill_ellipse(ctx, cx, belt_y, belt_rx, 4, C["armor_dark"])
    stroke_ellipse(ctx, cx, belt_y, belt_rx, 4, OUTLINE_GREEN, 1.5)

    # Arms
    shoulder_w = torso_rx * 0.9
    arm_len = 48
    for side in [-1, 1]:
        sx_arm = cx + side * shoulder_w + turn_side * 8
        sy_arm = torso_y + 8
        elbow_x = sx_arm + side * 14 * fw + turn_side * 5
        elbow_y = sy_arm + arm_len * 0.5
        hand_x = elbow_x + side * 6 * fw + turn_side * 3
        hand_y = elbow_y + arm_len * 0.4
        # Shoulder pad
        fill_circle(ctx, sx_arm, sy_arm, 8 * fw, C["armor_dark"])
        stroke_circle(ctx, sx_arm, sy_arm, 8 * fw, OUTLINE_GREEN, 2)
        draw_limb(ctx, sx_arm, sy_arm, elbow_x, elbow_y, 9 * fw, C["armor"])
        draw_limb(ctx, elbow_x, elbow_y, hand_x, hand_y, 7 * fw, C["skin"])
        fill_circle(ctx, hand_x, hand_y, 5, C["skin"])
        stroke_circle(ctx, hand_x, hand_y, 5, OUTLINE_GREEN, 1.5)

    # Neck
    draw_limb(ctx, cx + turn_side * 3, neck_y, cx + turn_side * 2, torso_y,
              9 * fw, C["skin"])

    # Head
    draw_head(ctx, cx + turn_side * 4, head_y, head_r, C["skin"])
    # Hair
    if facing < 0.5:
        fill_ellipse(ctx, cx + turn_side * 2, head_y - 3,
                     head_r * 0.9, head_r * 0.7, C["hair"])

    if facing > 0.1:
        draw_eyes(ctx, cx + turn_side * 4, head_y, head_r, C["eye"],
                  facing, eye_scale=1.0, turn_side=turn_side)


def _draw_zombie_base(ctx, cx, cy, facing, turn_side, C, arm_style="normal",
                      bulk=1.0):
    """Shared zombie drawing code."""
    abs_f = abs(facing)
    fw = 0.35 + abs_f * 0.65

    head_r = 19 * bulk
    head_y = cy - 100 * bulk
    neck_y = head_y + head_r + 4
    torso_y = neck_y + 8
    torso_h = 48 * bulk
    hip_y = torso_y + torso_h
    torso_rx = 26 * fw * bulk
    torso_ry = torso_h * 0.5

    # Legs
    leg_len = 55 * bulk
    leg_spread = 12 * fw * bulk
    for side in [-1, 1]:
        lx = cx + side * leg_spread
        # Shambling legs: slightly more spread
        draw_limb(ctx, lx, hip_y, lx + side * 6, hip_y + leg_len,
                  10 * fw * bulk, C["clothes_dark"])
        foot_x = lx + side * 6
        foot_y = hip_y + leg_len
        fill_ellipse(ctx, foot_x, foot_y + 2, 8, 4, C["clothes_dark"])
        stroke_ellipse(ctx, foot_x, foot_y + 2, 8, 4, OUTLINE_GREEN, 1.5)

    # Torso
    draw_3d_oval(ctx, cx, torso_y + torso_ry, torso_rx, torso_ry,
                 C["clothes"], turn_side=turn_side, facing=facing)

    # Torn clothing lines
    for i in range(3):
        ty = torso_y + 15 + i * 14
        tw = torso_rx * (0.6 - i * 0.1)
        draw_line(ctx, cx - tw, ty, cx - tw + 8, ty + 3,
                  C["clothes_dark"], 1.5)

    # Arms
    shoulder_w = torso_rx * 0.85
    arm_len = 45 * bulk
    for side in [-1, 1]:
        sx_arm = cx + side * shoulder_w + turn_side * 7
        sy_arm = torso_y + 10

        if arm_style == "shamble":
            # Arms stretched forward
            elbow_x = sx_arm + turn_side * 20 + side * 5 * fw
            elbow_y = sy_arm + 5
            hand_x = elbow_x + turn_side * 15 + side * 3
            hand_y = elbow_y + 8
        else:
            elbow_x = sx_arm + side * 12 * fw + turn_side * 5
            elbow_y = sy_arm + arm_len * 0.5
            hand_x = elbow_x + side * 5 * fw + turn_side * 3
            hand_y = elbow_y + arm_len * 0.35

        draw_limb(ctx, sx_arm, sy_arm, elbow_x, elbow_y, 8 * fw * bulk, C["clothes"])
        draw_limb(ctx, elbow_x, elbow_y, hand_x, hand_y, 6 * fw * bulk, C["skin"])
        fill_circle(ctx, hand_x, hand_y, 4 * bulk, C["skin"])
        stroke_circle(ctx, hand_x, hand_y, 4 * bulk, OUTLINE_GREEN, 1.5)

    # Neck (slightly crooked)
    draw_limb(ctx, cx + turn_side * 5, neck_y, cx + turn_side * 2, torso_y,
              7 * fw, C["skin"])

    # Head (slightly tilted for zombies)
    hx = cx + turn_side * 6
    draw_head(ctx, hx, head_y, head_r, C["skin"])

    if facing > 0.1:
        draw_eyes(ctx, hx, head_y, head_r, C["eye"],
                  facing, eye_scale=0.9, turn_side=turn_side,
                  pupil_color=(0.6, 0.5, 0.1))
        # Zombie mouth: jagged line
        mouth_cx = hx + turn_side * head_r * 0.4
        mouth_y = head_y + head_r * 0.4
        mw = head_r * 0.3 * (0.3 + abs_f * 0.7)
        for i in range(4):
            mx1 = mouth_cx - mw + i * mw * 0.5
            mx2 = mx1 + mw * 0.25
            my1 = mouth_y + (3 if i % 2 == 0 else -2)
            my2 = mouth_y + (-2 if i % 2 == 0 else 3)
            draw_line(ctx, mx1, my1, mx2, my2, C["clothes_dark"], 1.5)


def draw_zombie_walker(ctx, cx, cy, facing, turn_side):
    C = CHAR_COLORS["zombie_walker"]
    _draw_zombie_base(ctx, cx, cy, facing, turn_side, C, arm_style="shamble")


def draw_zombie_runner(ctx, cx, cy, facing, turn_side):
    C = CHAR_COLORS["zombie_runner"]
    _draw_zombie_base(ctx, cx, cy, facing, turn_side, C, arm_style="normal")


def draw_zombie_brute(ctx, cx, cy, facing, turn_side):
    C = CHAR_COLORS["zombie_brute"]
    _draw_zombie_base(ctx, cx, cy, facing, turn_side, C, arm_style="normal",
                      bulk=1.25)


def draw_skeleton(ctx, cx, cy, facing, turn_side):
    """Draw a skeleton with visible ribs."""
    C = CHAR_COLORS["skeleton"]
    abs_f = abs(facing)
    fw = 0.35 + abs_f * 0.65

    head_r = 18
    head_y = cy - 100
    neck_y = head_y + head_r + 4
    torso_y = neck_y + 8
    torso_h = 48
    hip_y = torso_y + torso_h
    torso_rx = 22 * fw
    torso_ry = torso_h * 0.5

    # Legs (bony)
    leg_len = 58
    leg_spread = 10 * fw
    for side in [-1, 1]:
        lx = cx + side * leg_spread
        # Thigh
        draw_limb(ctx, lx, hip_y, lx + side * 3, hip_y + leg_len * 0.5,
                  6 * fw, C["bone"])
        # Knee joint
        knee_x = lx + side * 3
        knee_y = hip_y + leg_len * 0.5
        fill_circle(ctx, knee_x, knee_y, 4 * fw, C["bone"])
        stroke_circle(ctx, knee_x, knee_y, 4 * fw, OUTLINE_GREEN, 1.5)
        # Shin
        draw_limb(ctx, knee_x, knee_y, knee_x + side * 2, hip_y + leg_len,
                  5 * fw, C["bone"])
        # Foot
        foot_x = knee_x + side * 2
        foot_y = hip_y + leg_len
        fill_ellipse(ctx, foot_x + turn_side * 3, foot_y + 2, 7, 3, C["bone_dark"])
        stroke_ellipse(ctx, foot_x + turn_side * 3, foot_y + 2, 7, 3, OUTLINE_GREEN, 1.5)

    # Spine (visible as a line)
    draw_limb(ctx, cx + turn_side * 2, torso_y, cx + turn_side * 1, hip_y,
              5 * fw, C["bone"])

    # Ribcage
    rib_count = 5
    for i in range(rib_count):
        ry_pos = torso_y + 8 + i * (torso_h - 16) / (rib_count - 1)
        t = i / (rib_count - 1)
        rib_w = torso_rx * (0.7 + 0.3 * math.sin(t * math.pi))
        draw_line(ctx, cx - rib_w + turn_side * 4, ry_pos,
                  cx + rib_w + turn_side * 4, ry_pos, C["bone"], 2)
        # Curved rib ends
        for side in [-1, 1]:
            rx_end = cx + side * rib_w + turn_side * 4
            draw_line(ctx, rx_end, ry_pos, rx_end + side * 2, ry_pos + 3,
                      C["bone"], 1.5)

    # Pelvis
    pelvis_w = 18 * fw
    draw_body_oval(ctx, cx, hip_y, pelvis_w, 8, C["bone"])

    # Arms (bony)
    shoulder_w = torso_rx * 0.9
    arm_len = 45
    for side in [-1, 1]:
        sx_arm = cx + side * shoulder_w + turn_side * 6
        sy_arm = torso_y + 8
        elbow_x = sx_arm + side * 14 * fw + turn_side * 5
        elbow_y = sy_arm + arm_len * 0.5
        hand_x = elbow_x + side * 6 * fw + turn_side * 3
        hand_y = elbow_y + arm_len * 0.35

        draw_limb(ctx, sx_arm, sy_arm, elbow_x, elbow_y, 5 * fw, C["bone"])
        fill_circle(ctx, elbow_x, elbow_y, 3 * fw, C["bone"])
        stroke_circle(ctx, elbow_x, elbow_y, 3 * fw, OUTLINE_GREEN, 1)
        draw_limb(ctx, elbow_x, elbow_y, hand_x, hand_y, 4 * fw, C["bone"])
        # Bony hand
        fill_circle(ctx, hand_x, hand_y, 4, C["bone_dark"])
        stroke_circle(ctx, hand_x, hand_y, 4, OUTLINE_GREEN, 1.5)

    # Shoulder blades
    for side in [-1, 1]:
        sx_s = cx + side * shoulder_w * 0.5 + turn_side * 5
        fill_circle(ctx, sx_s, torso_y + 5, 5 * fw, C["bone"])
        stroke_circle(ctx, sx_s, torso_y + 5, 5 * fw, OUTLINE_GREEN, 1.5)

    # Neck
    draw_limb(ctx, cx + turn_side * 3, neck_y, cx + turn_side * 2, torso_y,
              4 * fw, C["bone"])

    # Skull
    hx = cx + turn_side * 4
    draw_head(ctx, hx, head_y, head_r, C["bone"])

    if facing > 0.1:
        # Hollow eye sockets
        eye_spread = head_r * 0.3
        socket_r = head_r * 0.18
        sphere_shift = turn_side * head_r * 0.5
        for side in [-1, 1]:
            ex = hx + side * eye_spread * abs_f + sphere_shift
            ey = head_y - head_r * 0.05
            fill_ellipse(ctx, ex, ey, socket_r * (0.4 + abs_f * 0.6),
                         socket_r, C["eye"])
            stroke_ellipse(ctx, ex, ey, socket_r * (0.4 + abs_f * 0.6),
                           socket_r, OUTLINE_GREEN, 1)
        # Nose hole
        nose_x = hx + turn_side * head_r * 0.4
        fill_ellipse(ctx, nose_x, head_y + head_r * 0.15,
                     2.5 * (0.3 + abs_f * 0.7), 3, C["eye"])
        # Teeth
        teeth_y = head_y + head_r * 0.35
        teeth_w = head_r * 0.35 * (0.3 + abs_f * 0.7)
        teeth_cx = hx + turn_side * head_r * 0.4
        for i in range(5):
            tx = teeth_cx - teeth_w + i * teeth_w * 0.5
            draw_line(ctx, tx, teeth_y - 2, tx, teeth_y + 2, C["bone"], 1.5)
    else:
        # Back of skull: suture lines
        draw_line(ctx, hx, head_y - head_r * 0.5, hx, head_y + head_r * 0.3,
                  C["bone_dark"], 1)
        draw_line(ctx, hx - head_r * 0.4, head_y, hx + head_r * 0.4, head_y,
                  C["bone_dark"], 1)


# ── Animal drawing functions ───────────────────────────────────────

def draw_deer(ctx, cx, cy, facing, turn_side):
    """Draw a deer. Body is horizontal — wide from side, narrow from front."""
    C = CHAR_COLORS["deer"]
    abs_f = abs(facing)
    # Animals: side=wide, front=narrow (opposite of humanoids)
    side_amount = 1.0 - abs_f  # 1 when side-on, 0 when front/back
    fw = 0.35 + side_amount * 0.65

    body_rx = 40 * fw  # wide from side
    body_ry = 22
    body_y = cy + 10

    # Legs (4 legs, visibility depends on angle)
    leg_len = 55
    leg_positions = [
        (-0.6, -0.3, "front"),  # front-left
        (0.6, 0.3, "front"),    # front-right
        (-0.6, -0.3, "back"),   # back-left
        (0.6, 0.3, "back"),     # back-right
    ]
    for (side_offset, depth, pos) in leg_positions:
        # Calculate visibility: legs on far side are less visible
        leg_side = side_offset
        visibility = 0.4 + 0.6 * max(0, leg_side * turn_side + 0.5)
        if visibility < 0.2:
            continue

        if pos == "front":
            lx = cx + side_offset * body_rx * 0.7 + turn_side * body_rx * 0.3
            ly = body_y + body_ry * 0.6
        else:
            lx = cx + side_offset * body_rx * 0.7 - turn_side * body_rx * 0.2
            ly = body_y + body_ry * 0.7

        knee_y = ly + leg_len * 0.45
        foot_y = ly + leg_len
        draw_limb(ctx, lx, ly, lx, knee_y, 6, C["legs"])
        draw_limb(ctx, lx, knee_y, lx + turn_side * 3, foot_y, 5, C["legs"])
        # Hoof
        fill_ellipse(ctx, lx + turn_side * 3, foot_y + 1, 4, 2.5, (0.2, 0.15, 0.1))
        stroke_ellipse(ctx, lx + turn_side * 3, foot_y + 1, 4, 2.5, OUTLINE_GREEN, 1)

    # Body
    draw_3d_oval(ctx, cx, body_y, body_rx, body_ry,
                 C["body"], turn_side=turn_side, facing=facing)
    # Lighter belly
    fill_ellipse(ctx, cx - turn_side * body_rx * 0.1, body_y + body_ry * 0.3,
                 body_rx * 0.6, body_ry * 0.4, (*C["body_light"], 0.5))

    # Neck
    neck_base_x = cx + turn_side * body_rx * 0.5
    neck_base_y = body_y - body_ry * 0.4
    head_x = neck_base_x + turn_side * 15
    head_y = neck_base_y - 35
    draw_limb(ctx, neck_base_x, neck_base_y, head_x, head_y, 10, C["body"])

    # Head
    head_r = 14
    draw_head(ctx, head_x, head_y, head_r, C["body"])

    # Snout
    snout_x = head_x + turn_side * head_r * 0.7
    snout_y = head_y + head_r * 0.3
    snout_rx = head_r * 0.5 * (0.4 + abs_f * 0.6)
    fill_ellipse(ctx, snout_x, snout_y, snout_rx, head_r * 0.35, C["body_light"])
    stroke_ellipse(ctx, snout_x, snout_y, snout_rx, head_r * 0.35, OUTLINE_GREEN, 1.5)

    # Eyes
    if facing > 0.1:
        draw_eyes(ctx, head_x, head_y, head_r, C["eye"],
                  facing, eye_scale=0.7, turn_side=turn_side)
    elif abs_f < 0.3:
        # Side view: one eye visible
        ey = head_y - head_r * 0.1
        ex = head_x + turn_side * head_r * 0.35
        fill_circle(ctx, ex, ey, 3, (1.0, 1.0, 1.0))
        fill_circle(ctx, ex, ey, 1.5, C["eye"])

    # Ears
    for side in [-1, 1]:
        ear_vis = 0.3 + 0.7 * max(0, side * turn_side + 0.3)
        if ear_vis < 0.15:
            continue
        ear_x = head_x + side * head_r * 0.6 * (0.4 + abs_f * 0.6)
        ear_y = head_y - head_r * 0.8
        fill_ellipse(ctx, ear_x, ear_y, 4, 8, C["body"])
        stroke_ellipse(ctx, ear_x, ear_y, 4, 8, OUTLINE_GREEN, 1.5)

    # Antlers
    for side in [-1, 1]:
        antler_vis = 0.3 + 0.7 * max(0, side * turn_side + 0.3)
        if antler_vis < 0.15:
            continue
        ax = head_x + side * head_r * 0.4 * (0.4 + abs_f * 0.6)
        ay = head_y - head_r * 0.9
        # Main tine
        draw_line(ctx, ax, ay, ax + side * 8, ay - 20, C["antler"], 2.5)
        # Branch 1
        draw_line(ctx, ax + side * 4, ay - 10, ax + side * 12, ay - 15,
                  C["antler"], 2)
        # Branch 2
        draw_line(ctx, ax + side * 6, ay - 16, ax + side * 14, ay - 22,
                  C["antler"], 1.5)

    # Tail
    tail_x = cx - turn_side * body_rx * 0.6
    tail_y = body_y - body_ry * 0.2
    fill_ellipse(ctx, tail_x, tail_y, 5, 4, C["body_light"])
    stroke_ellipse(ctx, tail_x, tail_y, 5, 4, OUTLINE_GREEN, 1)


def draw_pig(ctx, cx, cy, facing, turn_side):
    """Draw a pig. Rounded body, snout, curly tail."""
    C = CHAR_COLORS["pig"]
    abs_f = abs(facing)
    side_amount = 1.0 - abs_f
    fw = 0.35 + side_amount * 0.65

    body_rx = 35 * fw
    body_ry = 25
    body_y = cy + 20

    # Legs (short and stubby)
    leg_len = 35
    leg_positions = [
        (-0.5, "front"), (0.5, "front"),
        (-0.5, "back"), (0.5, "back"),
    ]
    for (side_offset, pos) in leg_positions:
        visibility = 0.4 + 0.6 * max(0, side_offset * turn_side + 0.5)
        if visibility < 0.2:
            continue
        if pos == "front":
            lx = cx + side_offset * body_rx * 0.6 + turn_side * body_rx * 0.25
        else:
            lx = cx + side_offset * body_rx * 0.6 - turn_side * body_rx * 0.15
        ly = body_y + body_ry * 0.6
        draw_limb(ctx, lx, ly, lx, ly + leg_len, 8, C["legs"])
        # Hoof
        fill_ellipse(ctx, lx, ly + leg_len + 1, 5, 3, (0.3, 0.2, 0.2))
        stroke_ellipse(ctx, lx, ly + leg_len + 1, 5, 3, OUTLINE_GREEN, 1)

    # Body
    draw_3d_oval(ctx, cx, body_y, body_rx, body_ry,
                 C["body"], turn_side=turn_side, facing=facing)
    # Belly highlight
    fill_ellipse(ctx, cx - turn_side * 5, body_y + body_ry * 0.2,
                 body_rx * 0.5, body_ry * 0.4, (*C["body"], 0.4))

    # Head
    head_x = cx + turn_side * body_rx * 0.5
    head_y = body_y - body_ry * 0.5
    head_r = 16
    draw_head(ctx, head_x, head_y, head_r, C["body"])

    # Snout
    snout_x = head_x + turn_side * head_r * 0.8
    snout_y = head_y + head_r * 0.2
    snout_rx = head_r * 0.45 * (0.5 + abs_f * 0.5)
    snout_ry = head_r * 0.35
    fill_ellipse(ctx, snout_x, snout_y, snout_rx, snout_ry, C["snout"])
    stroke_ellipse(ctx, snout_x, snout_y, snout_rx, snout_ry, OUTLINE_GREEN, 1.5)
    # Nostrils
    if abs_f > 0.3 or abs(turn_side) > 0.5:
        for ns in [-1, 1]:
            nx = snout_x + ns * snout_rx * 0.35
            fill_circle(ctx, nx, snout_y, 1.5, C["body_dark"])

    # Eyes
    if facing > 0.1:
        draw_eyes(ctx, head_x, head_y, head_r, C["eye"],
                  facing, eye_scale=0.6, turn_side=turn_side)
    elif abs_f < 0.3:
        ex = head_x + turn_side * head_r * 0.3
        ey = head_y - head_r * 0.1
        fill_circle(ctx, ex, ey, 2.5, (1.0, 1.0, 1.0))
        fill_circle(ctx, ex, ey, 1.2, C["eye"])

    # Ears
    for side in [-1, 1]:
        ear_vis = 0.3 + 0.7 * max(0, side * turn_side + 0.3)
        if ear_vis < 0.15:
            continue
        ear_x = head_x + side * head_r * 0.55 * (0.4 + abs_f * 0.6)
        ear_y = head_y - head_r * 0.7
        # Floppy triangular ear
        ctx.move_to(ear_x, ear_y)
        ctx.line_to(ear_x + side * 6, ear_y - 8)
        ctx.line_to(ear_x + side * 10, ear_y + 2)
        ctx.close_path()
        set_color(ctx, *C["body"])
        ctx.fill_preserve()
        set_color(ctx, *OUTLINE_GREEN)
        ctx.set_line_width(1.5)
        ctx.stroke()

    # Curly tail
    tail_x = cx - turn_side * body_rx * 0.7
    tail_y = body_y - body_ry * 0.1
    # Draw a curly spiral
    ctx.move_to(tail_x, tail_y)
    ctx.curve_to(tail_x - turn_side * 5, tail_y - 8,
                 tail_x - turn_side * 12, tail_y - 5,
                 tail_x - turn_side * 10, tail_y + 2)
    ctx.curve_to(tail_x - turn_side * 8, tail_y + 8,
                 tail_x - turn_side * 3, tail_y + 5,
                 tail_x - turn_side * 5, tail_y - 2)
    set_color(ctx, *C["body"])
    ctx.set_line_width(3)
    ctx.stroke_preserve()
    set_color(ctx, *OUTLINE_GREEN)
    ctx.set_line_width(1)
    ctx.stroke()


def draw_sheep(ctx, cx, cy, facing, turn_side):
    """Draw a sheep. Fluffy wool body, dark face and legs."""
    C = CHAR_COLORS["sheep"]
    abs_f = abs(facing)
    side_amount = 1.0 - abs_f
    fw = 0.35 + side_amount * 0.65

    body_rx = 38 * fw
    body_ry = 28
    body_y = cy + 15

    # Legs (thin and dark)
    leg_len = 40
    leg_positions = [
        (-0.5, "front"), (0.5, "front"),
        (-0.5, "back"), (0.5, "back"),
    ]
    for (side_offset, pos) in leg_positions:
        visibility = 0.4 + 0.6 * max(0, side_offset * turn_side + 0.5)
        if visibility < 0.2:
            continue
        if pos == "front":
            lx = cx + side_offset * body_rx * 0.6 + turn_side * body_rx * 0.25
        else:
            lx = cx + side_offset * body_rx * 0.6 - turn_side * body_rx * 0.15
        ly = body_y + body_ry * 0.6
        draw_limb(ctx, lx, ly, lx, ly + leg_len, 6, C["legs"])
        # Hoof
        fill_ellipse(ctx, lx, ly + leg_len + 1, 4, 2.5, (0.15, 0.12, 0.10))
        stroke_ellipse(ctx, lx, ly + leg_len + 1, 4, 2.5, OUTLINE_GREEN, 1)

    # Fluffy wool body (larger, with bumpy outline effect)
    draw_3d_oval(ctx, cx, body_y, body_rx, body_ry,
                 C["wool"], turn_side=turn_side, facing=facing)
    # Wool texture: small overlapping bumps
    bump_count = 8
    for i in range(bump_count):
        angle = i * math.tau / bump_count
        bx = cx + math.cos(angle) * body_rx * 0.7
        by = body_y + math.sin(angle) * body_ry * 0.7
        bump_r = 8 + (i % 3) * 2
        fill_circle(ctx, bx, by, bump_r, (*C["wool"], 0.5))
        stroke_circle(ctx, bx, by, bump_r, (*OUTLINE_GREEN, 0.3), 1)

    # Head (dark face)
    head_x = cx + turn_side * body_rx * 0.5
    head_y = body_y - body_ry * 0.6
    head_r = 13
    # Wool tuft on top
    fill_circle(ctx, head_x, head_y - head_r * 0.7, 8, C["wool"])
    stroke_circle(ctx, head_x, head_y - head_r * 0.7, 8, OUTLINE_GREEN, 1.5)
    # Dark face
    draw_head(ctx, head_x, head_y, head_r, C["face"])

    # Eyes
    if facing > 0.1:
        draw_eyes(ctx, head_x, head_y, head_r, C["eye"],
                  facing, eye_scale=0.6, turn_side=turn_side,
                  pupil_color=(0.08, 0.06, 0.05))
    elif abs_f < 0.3:
        ex = head_x + turn_side * head_r * 0.3
        ey = head_y - head_r * 0.1
        fill_circle(ctx, ex, ey, 2.5, (0.85, 0.82, 0.78))
        fill_circle(ctx, ex, ey, 1.2, C["eye"])

    # Ears
    for side in [-1, 1]:
        ear_vis = 0.3 + 0.7 * max(0, side * turn_side + 0.3)
        if ear_vis < 0.15:
            continue
        ear_x = head_x + side * head_r * 0.7 * (0.4 + abs_f * 0.6)
        ear_y = head_y
        fill_ellipse(ctx, ear_x, ear_y, 6, 4, C["face"])
        stroke_ellipse(ctx, ear_x, ear_y, 6, 4, OUTLINE_GREEN, 1.5)

    # Tail (small wool puff)
    tail_x = cx - turn_side * body_rx * 0.6
    tail_y = body_y - body_ry * 0.15
    fill_circle(ctx, tail_x, tail_y, 7, C["wool"])
    stroke_circle(ctx, tail_x, tail_y, 7, OUTLINE_GREEN, 1.5)


# ── Character registry ────────────────────────────────────────────

CHARACTER_DRAW_FUNCS = {
    "mage": draw_mage,
    "warrior": draw_warrior,
    "zombie_walker": draw_zombie_walker,
    "zombie_runner": draw_zombie_runner,
    "zombie_brute": draw_zombie_brute,
    "skeleton": draw_skeleton,
    "deer": draw_deer,
    "pig": draw_pig,
    "sheep": draw_sheep,
}


# ── Rendering pipeline ────────────────────────────────────────────

def render_frame(draw_func, width, height, angle_deg):
    """Render a single frame for a character at a given angle.

    angle_deg: 0=front, 90=left, 180=back, 270=right
    Returns a cairo ImageSurface with transparent background.
    """
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(surface)

    # Transparent background (already default for ARGB32)

    # Convert angle to facing/turn_side
    angle_rad = math.radians(angle_deg)
    facing = math.cos(angle_rad)
    turn_side = -math.sin(angle_rad)  # negative so 90deg = left side

    cx = width / 2
    cy = height / 2 + 20  # offset down slightly so heads don't clip

    draw_func(ctx, cx, cy, facing, turn_side)

    return surface


def surface_to_png_bytes(surface):
    """Convert a cairo surface to PNG bytes."""
    import io
    buf = io.BytesIO()
    surface.write_to_png(buf)
    return buf.getvalue()


def generate_character(name, draw_func, num_angles, width, height, output_dir):
    """Generate all angle PNGs and sprite sheet for one character."""
    char_dir = output_dir / name
    char_dir.mkdir(parents=True, exist_ok=True)

    step = 360 / num_angles
    surfaces = []

    for i in range(num_angles):
        angle = i * step
        surface = render_frame(draw_func, width, height, angle)
        surfaces.append(surface)

        # Save individual frame
        angle_int = int(round(angle))
        fname = f"angle_{angle_int:03d}.png"
        surface.write_to_png(str(char_dir / fname))

    # Generate sprite sheet (6 columns)
    cols = 6
    rows = math.ceil(num_angles / cols)
    sheet_w = cols * width
    sheet_h = rows * height

    sheet = cairo.ImageSurface(cairo.FORMAT_ARGB32, sheet_w, sheet_h)
    ctx = cairo.Context(sheet)

    for i, surf in enumerate(surfaces):
        col = i % cols
        row = i // cols
        x = col * width
        y = row * height
        ctx.set_source_surface(surf, x, y)
        ctx.paint()

    sheet.write_to_png(str(char_dir / "sheet.png"))

    return len(surfaces)


# ── CLI ────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Generate multi-angle character sprite sheets using Cairo.")
    parser.add_argument(
        "--characters", nargs="*", default=None,
        help="Character names to generate (default: all)")
    parser.add_argument(
        "--angles", type=int, default=36,
        help="Number of angles (default: 36, i.e. every 10 degrees)")
    parser.add_argument(
        "--size", type=str, default="256x384",
        help="Frame size as WIDTHxHEIGHT (default: 256x384)")
    args = parser.parse_args()

    # Parse size
    parts = args.size.split("x")
    width = int(parts[0])
    height = int(parts[1])

    # Determine characters
    if args.characters:
        characters = {}
        for name in args.characters:
            if name not in CHARACTER_DRAW_FUNCS:
                print(f"Warning: unknown character '{name}', skipping")
                continue
            characters[name] = CHARACTER_DRAW_FUNCS[name]
    else:
        characters = CHARACTER_DRAW_FUNCS

    print(f"Generating sprites: {width}x{height}, {args.angles} angles")
    print(f"Characters: {', '.join(characters.keys())}")
    print(f"Output: {OUT_BASE}")
    print()

    for name, draw_func in characters.items():
        count = generate_character(name, draw_func, args.angles, width, height,
                                   OUT_BASE)
        print(f"  {name}: {count} frames + sheet.png")

    print("\nDone!")


if __name__ == "__main__":
    main()
