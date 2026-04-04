#!/usr/bin/env python3
"""Generate multi-angle character sprite sheets using Cairo.

Renders each character at 36 angles (every 10 degrees) into individual PNGs
and a combined sprite sheet. Uses The-Mount's character modules directly
for drawing -- no reinvented drawing code.

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
    python3 tools/generate_sprites.py --characters alice chicken mage
    python3 tools/generate_sprites.py --angles 72 --size 128x192
"""

import argparse
import math
import sys
from pathlib import Path

import cairo

# Add The-Mount to sys.path so we can import its character modules
sys.path.insert(0, "/home/david/The-Mount")
from characters import (
    alice, chicken, turkey, brain, waterbag,
    carrot, tornado, potato, skeleton, colonel, cat, cid,
)
from characters.base import (
    OUTLINE_GREEN, set_color, fill_circle, stroke_circle,
    fill_ellipse, stroke_ellipse, draw_line, draw_limb,
    draw_body_oval, draw_head, draw_3d_oval, draw_eyes,
)

SCRIPT_DIR = Path(__file__).parent
OUT_BASE = SCRIPT_DIR.parent / "assets" / "sprites" / "characters"


# ── Standing pose (joint positions for an idle character) ─────────

def make_standing_pose(cx=128, ground_y=340, height=200):
    """Create a standard standing pose joint dict."""
    return {
        "Head": (cx, ground_y - height),
        "Neck1": (cx, ground_y - height + 20),
        "Spine1": (cx, ground_y - height * 0.6),
        "Hips": (cx, ground_y - height * 0.4),
        "LeftArm": (cx + 30, ground_y - height * 0.55),
        "LeftForeArm": (cx + 35, ground_y - height * 0.35),
        "LeftHand": (cx + 38, ground_y - height * 0.2),
        "RightArm": (cx - 30, ground_y - height * 0.55),
        "RightForeArm": (cx - 35, ground_y - height * 0.35),
        "RightHand": (cx - 38, ground_y - height * 0.2),
        "LeftUpLeg": (cx + 12, ground_y - height * 0.35),
        "LeftLeg": (cx + 14, ground_y - height * 0.17),
        "LeftFoot": (cx + 15, ground_y),
        "RightUpLeg": (cx - 12, ground_y - height * 0.35),
        "RightLeg": (cx - 14, ground_y - height * 0.17),
        "RightFoot": (cx - 15, ground_y),
    }


# ── Game-specific character draw functions ───────────────────────
# These use The-Mount's base.py drawing helpers, same style as
# The-Mount characters, but take (ctx, J, facing, turn_side) like
# a simplified draw() call.

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


def _draw_game_mage(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    """Mage with wizard hat, robe, and staff."""
    if not all(k in J for k in ["Head", "Neck1", "Spine1", "Hips"]):
        return
    C = CHAR_COLORS["mage"]
    abs_f = abs(facing)
    fw = 0.35 + abs_f * 0.65

    hx, hy = J["Head"]
    nx, ny = J["Neck1"]
    sx, sy = J["Spine1"]
    hipx, hipy = J["Hips"]
    head_r = 22

    torso_rx = 28 * fw
    torso_ry = (hipy - sy) * 0.5

    # Legs
    for side_key in [("LeftUpLeg", "LeftLeg", "LeftFoot"),
                     ("RightUpLeg", "RightLeg", "RightFoot")]:
        if all(k in J for k in side_key):
            ux, uy = J[side_key[0]]
            kx, ky = J[side_key[1]]
            fx, fy = J[side_key[2]]
            draw_limb(ctx, ux, uy, kx, ky, 10 * fw, C["robe_dark"])
            draw_limb(ctx, kx, ky, fx, fy, 8 * fw, C["robe_dark"])
            fill_ellipse(ctx, fx + turn_side * 3, fy + 2, 8, 4, C["robe_dark"])
            stroke_ellipse(ctx, fx + turn_side * 3, fy + 2, 8, 4, OUTLINE_GREEN, 1.5)

    # Robe / torso
    draw_3d_oval(ctx, (sx + hipx) / 2, (sy + hipy) / 2, torso_rx, torso_ry,
                 C["robe"], turn_side=turn_side, facing=facing)
    # Robe skirt
    skirt_rx = torso_rx * 1.1
    draw_3d_oval(ctx, hipx, hipy, skirt_rx, 20,
                 C["robe_dark"], turn_side=turn_side, facing=facing)

    # Arms
    for arm_j, forearm_j, hand_j in [
        ("LeftArm", "LeftForeArm", "LeftHand"),
        ("RightArm", "RightForeArm", "RightHand"),
    ]:
        if arm_j in J and forearm_j in J:
            ax, ay = J[arm_j]
            fax, fay = J[forearm_j]
            draw_limb(ctx, ax, ay, fax, fay, 8 * fw, C["robe"])
            if hand_j in J:
                hax, hay = J[hand_j]
                draw_limb(ctx, fax, fay, hax, hay, 6 * fw, C["skin"])
                fill_circle(ctx, hax, hay, 4, C["skin"])
                stroke_circle(ctx, hax, hay, 4, OUTLINE_GREEN, 1.5)

    # Staff (right side)
    if "RightHand" in J:
        rhx, rhy = J["RightHand"]
        staff_top = hy - 30
        draw_limb(ctx, rhx, rhy, rhx + 2, staff_top, 4, C["staff"])
        fill_circle(ctx, rhx + 1, staff_top, 7, (0.6, 0.5, 0.95))
        stroke_circle(ctx, rhx + 1, staff_top, 7, OUTLINE_GREEN, 2)
        fill_circle(ctx, rhx - 1, staff_top - 2, 3, (0.8, 0.75, 1.0, 0.6))

    # Neck
    draw_limb(ctx, nx + turn_side * 3, ny, sx + turn_side * 2, sy, 8 * fw, C["skin"])

    # Head
    draw_head(ctx, hx + turn_side * 5, hy, head_r, C["skin"])

    # Wizard hat
    hat_cx = hx + turn_side * 5
    hat_base_y = hy - head_r + 2
    hat_tip_y = hy - head_r - 35
    hat_brim_hw = head_r + 8
    fill_ellipse(ctx, hat_cx, hat_base_y, hat_brim_hw * fw, 5, C["hat"])
    stroke_ellipse(ctx, hat_cx, hat_base_y, hat_brim_hw * fw, 5, OUTLINE_GREEN, 2)
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
        draw_eyes(ctx, hx + turn_side * 5, hy, head_r, C["eye"],
                  facing, eye_scale=1.0, turn_side=turn_side)
        beard_cx = hx + turn_side * head_r * 0.45 + turn_side * 5
        beard_y = hy + head_r * 0.4
        beard_w = head_r * 0.3 * (0.3 + abs_f * 0.7)
        for i in range(3):
            by = beard_y + i * 6
            bw = beard_w * (1.0 - i * 0.2)
            draw_line(ctx, beard_cx - bw, by, beard_cx + bw, by + 4, C["hair"], 2)


def _draw_game_warrior(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    """Warrior with armor."""
    if not all(k in J for k in ["Head", "Neck1", "Spine1", "Hips"]):
        return
    C = CHAR_COLORS["warrior"]
    abs_f = abs(facing)
    fw = 0.35 + abs_f * 0.65

    hx, hy = J["Head"]
    nx, ny = J["Neck1"]
    sx, sy = J["Spine1"]
    hipx, hipy = J["Hips"]
    head_r = 20

    torso_rx = 32 * fw
    torso_ry = (hipy - sy) * 0.5

    # Legs
    for side_key in [("LeftUpLeg", "LeftLeg", "LeftFoot"),
                     ("RightUpLeg", "RightLeg", "RightFoot")]:
        if all(k in J for k in side_key):
            ux, uy = J[side_key[0]]
            kx, ky = J[side_key[1]]
            fx, fy = J[side_key[2]]
            draw_limb(ctx, ux, uy, kx, ky, 12 * fw, C["pants"])
            draw_limb(ctx, kx, ky, fx, fy, 10 * fw, C["pants"])
            fill_ellipse(ctx, fx + turn_side * 3, fy + 2, 9, 5, C["armor_dark"])
            stroke_ellipse(ctx, fx + turn_side * 3, fy + 2, 9, 5, OUTLINE_GREEN, 1.5)

    # Torso (armor)
    draw_3d_oval(ctx, (sx + hipx) / 2, (sy + hipy) / 2, torso_rx, torso_ry,
                 C["armor"], turn_side=turn_side, facing=facing)
    # Belt
    belt_rx = torso_rx * 0.95
    fill_ellipse(ctx, hipx, hipy - 5, belt_rx, 4, C["armor_dark"])
    stroke_ellipse(ctx, hipx, hipy - 5, belt_rx, 4, OUTLINE_GREEN, 1.5)

    # Arms
    for arm_j, forearm_j, hand_j in [
        ("LeftArm", "LeftForeArm", "LeftHand"),
        ("RightArm", "RightForeArm", "RightHand"),
    ]:
        if arm_j in J and forearm_j in J:
            ax, ay = J[arm_j]
            fax, fay = J[forearm_j]
            fill_circle(ctx, ax, ay, 8 * fw, C["armor_dark"])
            stroke_circle(ctx, ax, ay, 8 * fw, OUTLINE_GREEN, 2)
            draw_limb(ctx, ax, ay, fax, fay, 9 * fw, C["armor"])
            if hand_j in J:
                hax, hay = J[hand_j]
                draw_limb(ctx, fax, fay, hax, hay, 7 * fw, C["skin"])
                fill_circle(ctx, hax, hay, 5, C["skin"])
                stroke_circle(ctx, hax, hay, 5, OUTLINE_GREEN, 1.5)

    # Neck
    draw_limb(ctx, nx + turn_side * 3, ny, sx + turn_side * 2, sy, 9 * fw, C["skin"])

    # Head
    draw_head(ctx, hx + turn_side * 4, hy, head_r, C["skin"])
    if facing < 0.5:
        fill_ellipse(ctx, hx + turn_side * 2, hy - 3,
                     head_r * 0.9, head_r * 0.7, C["hair"])
    if facing > 0.1:
        draw_eyes(ctx, hx + turn_side * 4, hy, head_r, C["eye"],
                  facing, eye_scale=1.0, turn_side=turn_side)


def _draw_zombie_base(ctx, J, facing=1.0, turn_side=0.0, C=None,
                      arm_style="normal", bulk=1.0, **kwargs):
    """Shared zombie drawing code."""
    if not all(k in J for k in ["Head", "Neck1", "Spine1", "Hips"]):
        return
    abs_f = abs(facing)
    fw = 0.35 + abs_f * 0.65

    hx, hy = J["Head"]
    nx, ny = J["Neck1"]
    sx, sy = J["Spine1"]
    hipx, hipy = J["Hips"]
    head_r = 19 * bulk

    torso_rx = 26 * fw * bulk
    torso_ry = (hipy - sy) * 0.5

    # Legs
    for side_key in [("LeftUpLeg", "LeftLeg", "LeftFoot"),
                     ("RightUpLeg", "RightLeg", "RightFoot")]:
        if all(k in J for k in side_key):
            ux, uy = J[side_key[0]]
            kx, ky = J[side_key[1]]
            fx, fy = J[side_key[2]]
            draw_limb(ctx, ux, uy, kx, ky, 10 * fw * bulk, C["clothes_dark"])
            draw_limb(ctx, kx, ky, fx, fy, 8 * fw * bulk, C["clothes_dark"])
            fill_ellipse(ctx, fx, fy + 2, 8, 4, C["clothes_dark"])
            stroke_ellipse(ctx, fx, fy + 2, 8, 4, OUTLINE_GREEN, 1.5)

    # Torso
    draw_3d_oval(ctx, (sx + hipx) / 2, (sy + hipy) / 2, torso_rx, torso_ry,
                 C["clothes"], turn_side=turn_side, facing=facing)
    # Torn clothing lines
    for i in range(3):
        ty = sy + 15 + i * 14
        tw = torso_rx * (0.6 - i * 0.1)
        draw_line(ctx, hipx - tw, ty, hipx - tw + 8, ty + 3, C["clothes_dark"], 1.5)

    # Arms
    for arm_j, forearm_j, hand_j in [
        ("LeftArm", "LeftForeArm", "LeftHand"),
        ("RightArm", "RightForeArm", "RightHand"),
    ]:
        if arm_j in J and forearm_j in J:
            ax, ay = J[arm_j]
            fax, fay = J[forearm_j]
            if arm_style == "shamble":
                # Arms stretched forward
                fax = ax + turn_side * 20
                fay = ay + 5
            draw_limb(ctx, ax, ay, fax, fay, 8 * fw * bulk, C["clothes"])
            if hand_j in J:
                hax, hay = J[hand_j]
                if arm_style == "shamble":
                    hax = fax + turn_side * 15
                    hay = fay + 8
                draw_limb(ctx, fax, fay, hax, hay, 6 * fw * bulk, C["skin"])
                fill_circle(ctx, hax, hay, 4 * bulk, C["skin"])
                stroke_circle(ctx, hax, hay, 4 * bulk, OUTLINE_GREEN, 1.5)

    # Neck (slightly crooked)
    draw_limb(ctx, nx + turn_side * 5, ny, sx + turn_side * 2, sy, 7 * fw, C["skin"])

    # Head (slightly tilted)
    head_x = hx + turn_side * 6
    draw_head(ctx, head_x, hy, head_r, C["skin"])

    if facing > 0.1:
        draw_eyes(ctx, head_x, hy, head_r, C["eye"],
                  facing, eye_scale=0.9, turn_side=turn_side,
                  pupil_color=(0.6, 0.5, 0.1))
        mouth_cx = head_x + turn_side * head_r * 0.4
        mouth_y = hy + head_r * 0.4
        mw = head_r * 0.3 * (0.3 + abs_f * 0.7)
        for i in range(4):
            mx1 = mouth_cx - mw + i * mw * 0.5
            mx2 = mx1 + mw * 0.25
            my1 = mouth_y + (3 if i % 2 == 0 else -2)
            my2 = mouth_y + (-2 if i % 2 == 0 else 3)
            draw_line(ctx, mx1, my1, mx2, my2, C["clothes_dark"], 1.5)


def _draw_game_zombie_walker(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    _draw_zombie_base(ctx, J, facing, turn_side,
                      C=CHAR_COLORS["zombie_walker"], arm_style="shamble")


def _draw_game_zombie_runner(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    _draw_zombie_base(ctx, J, facing, turn_side,
                      C=CHAR_COLORS["zombie_runner"], arm_style="normal")


def _draw_game_zombie_brute(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    _draw_zombie_base(ctx, J, facing, turn_side,
                      C=CHAR_COLORS["zombie_brute"], arm_style="normal", bulk=1.25)


def _draw_game_deer(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    """Deer -- horizontal body, mapped from humanoid skeleton."""
    if not all(k in J for k in ["Head", "Spine1", "Hips"]):
        return
    C = CHAR_COLORS["deer"]
    abs_f = abs(facing)
    side_amount = 1.0 - abs_f
    fw = 0.35 + side_amount * 0.65

    sx, sy = J["Spine1"]
    hipx, hipy = J["Hips"]
    hx, hy = J["Head"]

    body_cx = (sx + hipx) / 2
    body_cy = (sy + hipy) / 2
    body_rx = 40 * fw
    body_ry = 22

    # Legs
    leg_len = 55
    leg_positions = [(-0.6, "front"), (0.6, "front"), (-0.6, "back"), (0.6, "back")]
    for (side_offset, pos) in leg_positions:
        visibility = 0.4 + 0.6 * max(0, side_offset * turn_side + 0.5)
        if visibility < 0.2:
            continue
        if pos == "front":
            lx = body_cx + side_offset * body_rx * 0.7 + turn_side * body_rx * 0.3
            ly = body_cy + body_ry * 0.6
        else:
            lx = body_cx + side_offset * body_rx * 0.7 - turn_side * body_rx * 0.2
            ly = body_cy + body_ry * 0.7
        knee_y = ly + leg_len * 0.45
        foot_y = ly + leg_len
        draw_limb(ctx, lx, ly, lx, knee_y, 6, C["legs"])
        draw_limb(ctx, lx, knee_y, lx + turn_side * 3, foot_y, 5, C["legs"])
        fill_ellipse(ctx, lx + turn_side * 3, foot_y + 1, 4, 2.5, (0.2, 0.15, 0.1))
        stroke_ellipse(ctx, lx + turn_side * 3, foot_y + 1, 4, 2.5, OUTLINE_GREEN, 1)

    # Body
    draw_3d_oval(ctx, body_cx, body_cy, body_rx, body_ry,
                 C["body"], turn_side=turn_side, facing=facing)
    fill_ellipse(ctx, body_cx - turn_side * body_rx * 0.1, body_cy + body_ry * 0.3,
                 body_rx * 0.6, body_ry * 0.4, (*C["body_light"], 0.5))

    # Neck
    neck_base_x = body_cx + turn_side * body_rx * 0.5
    neck_base_y = body_cy - body_ry * 0.4
    head_x = neck_base_x + turn_side * 15
    head_y = neck_base_y - 35
    draw_limb(ctx, neck_base_x, neck_base_y, head_x, head_y, 10, C["body"])

    # Head
    head_r = 14
    draw_head(ctx, head_x, head_y, head_r, C["body"])
    snout_x = head_x + turn_side * head_r * 0.7
    snout_y = head_y + head_r * 0.3
    snout_rx = head_r * 0.5 * (0.4 + abs_f * 0.6)
    fill_ellipse(ctx, snout_x, snout_y, snout_rx, head_r * 0.35, C["body_light"])
    stroke_ellipse(ctx, snout_x, snout_y, snout_rx, head_r * 0.35, OUTLINE_GREEN, 1.5)

    if facing > 0.1:
        draw_eyes(ctx, head_x, head_y, head_r, C["eye"],
                  facing, eye_scale=0.7, turn_side=turn_side)
    elif abs_f < 0.3:
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
        draw_line(ctx, ax, ay, ax + side * 8, ay - 20, C["antler"], 2.5)
        draw_line(ctx, ax + side * 4, ay - 10, ax + side * 12, ay - 15, C["antler"], 2)
        draw_line(ctx, ax + side * 6, ay - 16, ax + side * 14, ay - 22, C["antler"], 1.5)

    # Tail
    tail_x = body_cx - turn_side * body_rx * 0.6
    tail_y = body_cy - body_ry * 0.2
    fill_ellipse(ctx, tail_x, tail_y, 5, 4, C["body_light"])
    stroke_ellipse(ctx, tail_x, tail_y, 5, 4, OUTLINE_GREEN, 1)


def _draw_game_pig(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    """Pig -- rounded body, snout, curly tail."""
    if not all(k in J for k in ["Spine1", "Hips"]):
        return
    C = CHAR_COLORS["pig"]
    abs_f = abs(facing)
    side_amount = 1.0 - abs_f
    fw = 0.35 + side_amount * 0.65

    sx, sy = J["Spine1"]
    hipx, hipy = J["Hips"]
    body_cx = (sx + hipx) / 2
    body_cy = (sy + hipy) / 2
    body_rx = 35 * fw
    body_ry = 25

    # Legs
    leg_len = 35
    for (side_offset, pos) in [(-0.5, "front"), (0.5, "front"),
                                (-0.5, "back"), (0.5, "back")]:
        visibility = 0.4 + 0.6 * max(0, side_offset * turn_side + 0.5)
        if visibility < 0.2:
            continue
        if pos == "front":
            lx = body_cx + side_offset * body_rx * 0.6 + turn_side * body_rx * 0.25
        else:
            lx = body_cx + side_offset * body_rx * 0.6 - turn_side * body_rx * 0.15
        ly = body_cy + body_ry * 0.6
        draw_limb(ctx, lx, ly, lx, ly + leg_len, 8, C["legs"])
        fill_ellipse(ctx, lx, ly + leg_len + 1, 5, 3, (0.3, 0.2, 0.2))
        stroke_ellipse(ctx, lx, ly + leg_len + 1, 5, 3, OUTLINE_GREEN, 1)

    # Body
    draw_3d_oval(ctx, body_cx, body_cy, body_rx, body_ry,
                 C["body"], turn_side=turn_side, facing=facing)
    fill_ellipse(ctx, body_cx - turn_side * 5, body_cy + body_ry * 0.2,
                 body_rx * 0.5, body_ry * 0.4, (*C["body"], 0.4))

    # Head
    head_x = body_cx + turn_side * body_rx * 0.5
    head_y = body_cy - body_ry * 0.5
    head_r = 16
    draw_head(ctx, head_x, head_y, head_r, C["body"])

    # Snout
    snout_x = head_x + turn_side * head_r * 0.8
    snout_y = head_y + head_r * 0.2
    snout_rx = head_r * 0.45 * (0.5 + abs_f * 0.5)
    snout_ry = head_r * 0.35
    fill_ellipse(ctx, snout_x, snout_y, snout_rx, snout_ry, C["snout"])
    stroke_ellipse(ctx, snout_x, snout_y, snout_rx, snout_ry, OUTLINE_GREEN, 1.5)
    if abs_f > 0.3 or abs(turn_side) > 0.5:
        for ns in [-1, 1]:
            nx = snout_x + ns * snout_rx * 0.35
            fill_circle(ctx, nx, snout_y, 1.5, C["body_dark"])

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
    tail_x = body_cx - turn_side * body_rx * 0.7
    tail_y = body_cy - body_ry * 0.1
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


def _draw_game_sheep(ctx, J, facing=1.0, turn_side=0.0, **kwargs):
    """Sheep -- fluffy wool body, dark face and legs."""
    if not all(k in J for k in ["Spine1", "Hips"]):
        return
    C = CHAR_COLORS["sheep"]
    abs_f = abs(facing)
    side_amount = 1.0 - abs_f
    fw = 0.35 + side_amount * 0.65

    sx, sy = J["Spine1"]
    hipx, hipy = J["Hips"]
    body_cx = (sx + hipx) / 2
    body_cy = (sy + hipy) / 2
    body_rx = 38 * fw
    body_ry = 28

    # Legs
    leg_len = 40
    for (side_offset, pos) in [(-0.5, "front"), (0.5, "front"),
                                (-0.5, "back"), (0.5, "back")]:
        visibility = 0.4 + 0.6 * max(0, side_offset * turn_side + 0.5)
        if visibility < 0.2:
            continue
        if pos == "front":
            lx = body_cx + side_offset * body_rx * 0.6 + turn_side * body_rx * 0.25
        else:
            lx = body_cx + side_offset * body_rx * 0.6 - turn_side * body_rx * 0.15
        ly = body_cy + body_ry * 0.6
        draw_limb(ctx, lx, ly, lx, ly + leg_len, 6, C["legs"])
        fill_ellipse(ctx, lx, ly + leg_len + 1, 4, 2.5, (0.15, 0.12, 0.10))
        stroke_ellipse(ctx, lx, ly + leg_len + 1, 4, 2.5, OUTLINE_GREEN, 1)

    # Wool body
    draw_3d_oval(ctx, body_cx, body_cy, body_rx, body_ry,
                 C["wool"], turn_side=turn_side, facing=facing)
    bump_count = 8
    for i in range(bump_count):
        angle = i * math.tau / bump_count
        bx = body_cx + math.cos(angle) * body_rx * 0.7
        by = body_cy + math.sin(angle) * body_ry * 0.7
        bump_r = 8 + (i % 3) * 2
        fill_circle(ctx, bx, by, bump_r, (*C["wool"], 0.5))
        stroke_circle(ctx, bx, by, bump_r, (*OUTLINE_GREEN, 0.3), 1)

    # Head (dark face)
    head_x = body_cx + turn_side * body_rx * 0.5
    head_y = body_cy - body_ry * 0.6
    head_r = 13
    fill_circle(ctx, head_x, head_y - head_r * 0.7, 8, C["wool"])
    stroke_circle(ctx, head_x, head_y - head_r * 0.7, 8, OUTLINE_GREEN, 1.5)
    draw_head(ctx, head_x, head_y, head_r, C["face"])

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

    # Tail
    tail_x = body_cx - turn_side * body_rx * 0.6
    tail_y = body_cy - body_ry * 0.15
    fill_circle(ctx, tail_x, tail_y, 7, C["wool"])
    stroke_circle(ctx, tail_x, tail_y, 7, OUTLINE_GREEN, 1.5)


# ── Character registry ────────────────────────────────────────────
# Maps name -> (module_or_func, is_the_mount_module)
# The-Mount modules have draw(ctx, J, ..., facing=, turn_side=)
# Game-specific funcs have draw(ctx, J, facing=, turn_side=)

CHARACTER_REGISTRY = {
    # The-Mount characters (imported modules with draw() functions)
    "alice": alice,
    "chicken": chicken,
    "turkey": turkey,
    "brain": brain,
    "waterbag": waterbag,
    "carrot": carrot,
    "tornado": tornado,
    "potato": potato,
    "skeleton": skeleton,
    "colonel": colonel,
    "cat": cat,
    "cid": cid,
    # Game-specific characters (local draw functions)
    "mage": _draw_game_mage,
    "warrior": _draw_game_warrior,
    "zombie_walker": _draw_game_zombie_walker,
    "zombie_runner": _draw_game_zombie_runner,
    "zombie_brute": _draw_game_zombie_brute,
    "deer": _draw_game_deer,
    "pig": _draw_game_pig,
    "sheep": _draw_game_sheep,
}


# ── Rendering pipeline ────────────────────────────────────────────

def render_character_frame(char_entry, J, width, height, facing, turn_side):
    """Render a single frame for a character.

    char_entry: either a module (with .draw()) or a callable.
    Returns a cairo ImageSurface with transparent background.
    """
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(surface)

    # Transparent background
    ctx.set_operator(cairo.OPERATOR_CLEAR)
    ctx.paint()
    ctx.set_operator(cairo.OPERATOR_OVER)

    # Call the draw function
    if hasattr(char_entry, 'draw'):
        # It's a The-Mount module
        char_entry.draw(ctx, J, facing=facing, turn_side=turn_side)
    else:
        # It's a local draw function
        char_entry(ctx, J, facing=facing, turn_side=turn_side)

    return surface


def generate_character(name, char_entry, num_angles, width, height, output_dir):
    """Generate all angle PNGs and sprite sheet for one character."""
    char_dir = output_dir / name
    char_dir.mkdir(parents=True, exist_ok=True)

    step = 360 / num_angles
    surfaces = []

    cx = width / 2
    ground_y = height - 44  # leave some room at bottom
    pose_height = height * 0.52

    for i in range(num_angles):
        angle_deg = i * step
        angle_rad = math.radians(angle_deg)
        facing = math.cos(angle_rad)
        turn_side = -math.sin(angle_rad)  # negative so 90deg = left side

        J = make_standing_pose(cx=cx, ground_y=ground_y, height=pose_height)
        surface = render_character_frame(char_entry, J, width, height,
                                         facing, turn_side)
        surfaces.append(surface)

        # Save individual frame
        angle_int = int(round(angle_deg))
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
            if name not in CHARACTER_REGISTRY:
                print(f"Warning: unknown character '{name}', skipping")
                continue
            characters[name] = CHARACTER_REGISTRY[name]
    else:
        characters = CHARACTER_REGISTRY

    print(f"Generating sprites: {width}x{height}, {args.angles} angles")
    print(f"Characters: {', '.join(characters.keys())}")
    print(f"Output: {OUT_BASE}")
    print()

    for name, char_entry in characters.items():
        count = generate_character(name, char_entry, args.angles, width, height,
                                    OUT_BASE)
        print(f"  {name}: {count} frames + sheet.png")

    print("\nDone!")


if __name__ == "__main__":
    main()
