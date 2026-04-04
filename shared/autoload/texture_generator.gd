extends Node
## Procedural Texture Generator - Creates all 2D pixel art textures
## Generates epic mage, zombie, tree, and spell textures

# Texture cache
var texture_cache: Dictionary = {}

# Color palettes
const MAGE_ROBES := {
	"blue": [Color(0.2, 0.3, 0.7), Color(0.3, 0.4, 0.8), Color(0.15, 0.2, 0.5)],
	"red": [Color(0.7, 0.2, 0.2), Color(0.8, 0.3, 0.3), Color(0.5, 0.15, 0.15)],
	"purple": [Color(0.5, 0.2, 0.6), Color(0.6, 0.3, 0.7), Color(0.35, 0.1, 0.4)],
	"green": [Color(0.2, 0.5, 0.3), Color(0.3, 0.6, 0.4), Color(0.1, 0.35, 0.2)],
	"white": [Color(0.85, 0.85, 0.9), Color(0.95, 0.95, 1.0), Color(0.7, 0.7, 0.75)],
}

const SKIN_TONES := [
	Color(0.96, 0.80, 0.69),  # Light
	Color(0.87, 0.72, 0.53),  # Medium
	Color(0.76, 0.57, 0.42),  # Tan
	Color(0.55, 0.38, 0.26),  # Brown
	Color(0.36, 0.25, 0.18),  # Dark
]

const ZOMBIE_COLORS := {
	"walker": [Color(0.4, 0.5, 0.35), Color(0.5, 0.6, 0.4), Color(0.3, 0.4, 0.25)],
	"runner": [Color(0.5, 0.35, 0.3), Color(0.6, 0.4, 0.35), Color(0.4, 0.25, 0.2)],
	"brute": [Color(0.45, 0.4, 0.35), Color(0.55, 0.5, 0.45), Color(0.35, 0.3, 0.25)],
	"mage_zombie": [Color(0.35, 0.3, 0.5), Color(0.45, 0.4, 0.6), Color(0.25, 0.2, 0.4)],
	"exploder": [Color(0.6, 0.4, 0.3), Color(0.7, 0.5, 0.35), Color(0.5, 0.3, 0.2)],
}

const TREE_COLORS := {
	"oak": {"trunk": Color(0.4, 0.3, 0.2), "leaves": Color(0.2, 0.5, 0.2)},
	"pine": {"trunk": Color(0.35, 0.25, 0.15), "leaves": Color(0.1, 0.4, 0.2)},
	"dead": {"trunk": Color(0.3, 0.25, 0.2), "leaves": Color(0.4, 0.35, 0.3)},
	"magic": {"trunk": Color(0.3, 0.2, 0.4), "leaves": Color(0.5, 0.3, 0.7)},
	"swamp": {"trunk": Color(0.25, 0.3, 0.2), "leaves": Color(0.3, 0.4, 0.25)},
	# Biome-specific trees
	"cactus": {"trunk": Color(0.3, 0.55, 0.25), "leaves": Color(0.35, 0.6, 0.3)},  # Desert
	"palm": {"trunk": Color(0.5, 0.4, 0.25), "leaves": Color(0.25, 0.5, 0.2)},  # Desert
	"frost_pine": {"trunk": Color(0.45, 0.5, 0.55), "leaves": Color(0.85, 0.9, 0.95)},  # Mountain
	"crystal_tree": {"trunk": Color(0.4, 0.3, 0.5), "leaves": Color(0.9, 0.4, 1.0)},  # Wizardland
	"ember_tree": {"trunk": Color(0.15, 0.08, 0.05), "leaves": Color(0.9, 0.3, 0.1)},  # Hell
	"dark_oak": {"trunk": Color(0.15, 0.12, 0.1), "leaves": Color(0.05, 0.15, 0.1)},  # Dark Forest
}

func _ready() -> void:
	print("[TextureGenerator] Ready - generating textures on demand")

# ============================================
# MAGE PLAYER TEXTURES (64x96 pixels)
# ============================================
func generate_mage_texture(robe_color: String = "blue", skin_idx: int = 0, view_angle: String = "front") -> ImageTexture:
	var cache_key := "mage_%s_%d_%s" % [robe_color, skin_idx, view_angle]
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	var robe: Array = MAGE_ROBES.get(robe_color, MAGE_ROBES["blue"])
	var skin: Color = SKIN_TONES[clamp(skin_idx, 0, SKIN_TONES.size() - 1)]

	img.fill(Color(0, 0, 0, 0))

	match view_angle:
		"front":
			_draw_mage_front(img, robe, skin)
		"back":
			_draw_mage_back(img, robe, skin)
		"side":
			_draw_mage_side(img, robe, skin)
		_:
			_draw_mage_front(img, robe, skin)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

# --- Helper: safe pixel set ---
func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, c)

# --- Helper: fill an ellipse area ---
func _fill_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx: float = (x - cx) / rx
			var dy: float = (y - cy) / ry
			if dx * dx + dy * dy < 1.0:
				_px(img, x, y, color)

# --- Helper: fill a rectangle ---
func _fill_rect(img: Image, x1: int, y1: int, x2: int, y2: int, color: Color) -> void:
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			_px(img, x, y, color)

# --- Helper: fill a triangle (3 points) ---
func _fill_triangle(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, color: Color) -> void:
	var min_y: int = int(min(p0.y, min(p1.y, p2.y)))
	var max_y: int = int(max(p0.y, max(p1.y, p2.y)))
	var min_x: int = int(min(p0.x, min(p1.x, p2.x)))
	var max_x: int = int(max(p0.x, max(p1.x, p2.x)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var v0 := p2 - p0
			var v1 := p1 - p0
			var v2 := Vector2(x, y) - p0
			var d00 := v0.dot(v0)
			var d01 := v0.dot(v1)
			var d02 := v0.dot(v2)
			var d11 := v1.dot(v1)
			var d12 := v1.dot(v2)
			var inv := 1.0 / (d00 * d11 - d01 * d01 + 0.0001)
			var u := (d11 * d02 - d01 * d12) * inv
			var v := (d00 * d12 - d01 * d02) * inv
			if u >= 0 and v >= 0 and u + v <= 1:
				_px(img, x, y, color)

# --- Helper: draw a line (Bresenham) ---
func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var cx := x0
	var cy := y0
	for _i in range(200):
		_px(img, cx, cy, color)
		if cx == x1 and cy == y1:
			break
		var e2: int = err * 2
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy

# --- Helper: apply 1-pixel outline around all non-transparent pixels ---
func _apply_outline(img: Image, outline_color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var edge_pixels: Array = []
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1:
				# Check if any neighbor is transparent
				var is_edge := false
				for d in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or nx >= w or ny < 0 or ny >= h or img.get_pixel(nx, ny).a < 0.1:
						is_edge = true
						break
				if is_edge:
					edge_pixels.append(Vector2i(x, y))
	for p in edge_pixels:
		img.set_pixel(p.x, p.y, outline_color)

# --- Helper: apply left-side lighting ---
func _apply_lighting(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	# Find bounding box of non-transparent pixels
	var min_x := w
	var max_x := 0
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1:
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
	var mid_x := (min_x + max_x) / 2.0
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a > 0.1:
				var factor: float
				if x < mid_x:
					factor = 1.08 + randf() * 0.04
				else:
					factor = 0.85 + randf() * 0.04
				c.r = clampf(c.r * factor, 0, 1)
				c.g = clampf(c.g * factor, 0, 1)
				c.b = clampf(c.b * factor, 0, 1)
				img.set_pixel(x, y, c)

# ============================================
# MAGE DRAWING FUNCTIONS
# ============================================

func _draw_mage_front(img: Image, robe: Array, skin: Color) -> void:
	var cx := 32
	var by := 92  # Bottom of sprite

	var robe_main: Color = robe[0]
	var robe_light: Color = robe[1]
	var robe_dark: Color = robe[2]
	var hat_color := robe_main * 0.9
	var belt_color := Color(0.45, 0.35, 0.2)
	var boot_color := Color(0.35, 0.25, 0.15)
	var eye_white := Color(0.95, 0.95, 0.95)
	var eye_pupil := Color(0.1, 0.1, 0.15)
	var outline := Color(0.12, 0.08, 0.08)

	# --- Boots poking out at bottom ---
	_fill_ellipse(img, cx - 7, by - 2, 5, 3, boot_color)
	_fill_ellipse(img, cx + 7, by - 2, 5, 3, boot_color)

	# --- Robe body (trapezoid shape - wider at bottom) ---
	for y in range(by - 48, by - 2):
		var progress: float = (y - (by - 48)) / 46.0
		var half_w: int = int(8 + progress * 12)
		for x in range(cx - half_w, cx + half_w + 1):
			var shade: float = 0.93 + randf() * 0.07
			_px(img, x, y, robe_main * shade)

	# --- Belt across the waist ---
	_fill_rect(img, cx - 12, by - 30, cx + 12, by - 28, belt_color)
	# Belt buckle
	_fill_rect(img, cx - 2, by - 30, cx + 2, by - 28, Color(0.7, 0.6, 0.2))

	# --- Sleeves and hands ---
	# Left sleeve
	_fill_ellipse(img, cx - 14, by - 38, 5, 7, robe_dark)
	# Left hand
	_fill_ellipse(img, cx - 14, by - 30, 3, 3, skin)
	# Right sleeve
	_fill_ellipse(img, cx + 14, by - 38, 5, 7, robe_dark)
	# Right hand
	_fill_ellipse(img, cx + 14, by - 30, 3, 3, skin)

	# --- Neck ---
	_fill_rect(img, cx - 3, by - 50, cx + 3, by - 48, skin)

	# --- Head (oval) ---
	_fill_ellipse(img, cx, by - 57, 8, 8, skin)

	# --- Eyes (large, friendly) ---
	# Left eye
	_fill_ellipse(img, cx - 4, by - 58, 3, 2.5, eye_white)
	_fill_ellipse(img, cx - 4, by - 58, 1.5, 1.5, eye_pupil)
	# Right eye
	_fill_ellipse(img, cx + 4, by - 58, 3, 2.5, eye_white)
	_fill_ellipse(img, cx + 4, by - 58, 1.5, 1.5, eye_pupil)
	# Eyebrows
	_fill_rect(img, cx - 6, by - 62, cx - 2, by - 61, Color(0.3, 0.2, 0.15))
	_fill_rect(img, cx + 2, by - 62, cx + 6, by - 61, Color(0.3, 0.2, 0.15))

	# --- Mouth (small smile) ---
	_px(img, cx - 1, by - 53, Color(0.6, 0.3, 0.3))
	_px(img, cx, by - 53, Color(0.6, 0.3, 0.3))
	_px(img, cx + 1, by - 53, Color(0.6, 0.3, 0.3))

	# --- Pointy wizard hat ---
	# Hat brim (wide ellipse)
	_fill_ellipse(img, cx, by - 63, 12, 3, hat_color)
	# Hat cone
	_fill_triangle(img, Vector2(cx - 10, by - 64), Vector2(cx + 10, by - 64), Vector2(cx, by - 88), hat_color * 1.1)
	# Hat band
	_fill_rect(img, cx - 9, by - 66, cx + 9, by - 64, Color(0.6, 0.5, 0.15))
	# Hat tip star
	_draw_star(img, cx, int(by - 87), Color(1.0, 0.95, 0.5))

	# --- Robe hem detail ---
	for x in range(cx - 19, cx + 20):
		var shade := 0.85 + randf() * 0.1
		_px(img, x, by - 3, robe_dark * shade)
		_px(img, x, by - 4, robe_dark * shade)

	# Apply outline and lighting
	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_mage_back(img: Image, robe: Array, skin: Color) -> void:
	var cx := 32
	var by := 92

	var robe_main: Color = robe[0]
	var robe_dark: Color = robe[2]
	var hat_color := robe_main * 0.9
	var belt_color := Color(0.45, 0.35, 0.2)
	var boot_color := Color(0.35, 0.25, 0.15)
	var outline := Color(0.12, 0.08, 0.08)

	# --- Boots ---
	_fill_ellipse(img, cx - 7, by - 2, 5, 3, boot_color)
	_fill_ellipse(img, cx + 7, by - 2, 5, 3, boot_color)

	# --- Robe body (back view - cape draping) ---
	for y in range(by - 48, by - 2):
		var progress: float = (y - (by - 48)) / 46.0
		var half_w: int = int(8 + progress * 12)
		for x in range(cx - half_w, cx + half_w + 1):
			var shade: float = 0.90 + randf() * 0.07
			# Cape fold lines down the center
			var fold: int = abs(x - cx)
			if fold < 2:
				shade *= 0.9
			_px(img, x, y, robe_dark * shade)

	# --- Cape overlay (slightly different shade for depth) ---
	for y in range(by - 46, by - 5):
		var progress: float = (y - (by - 46)) / 41.0
		var half_w: int = int(6 + progress * 10)
		for x in range(cx - half_w, cx + half_w + 1):
			var shade: float = 0.92 + randf() * 0.06
			_px(img, x, y, robe_main * shade)

	# --- Belt (from behind) ---
	_fill_rect(img, cx - 12, by - 30, cx + 12, by - 28, belt_color)

	# --- Sleeves ---
	_fill_ellipse(img, cx - 14, by - 38, 5, 7, robe_dark)
	_fill_ellipse(img, cx + 14, by - 38, 5, 7, robe_dark)

	# --- Back of head ---
	_fill_ellipse(img, cx, by - 57, 8, 8, skin * 0.95)
	# Hair on back of head
	_fill_ellipse(img, cx, by - 58, 9, 7, Color(0.3, 0.2, 0.15))

	# --- Back of hat ---
	_fill_ellipse(img, cx, by - 63, 12, 3, hat_color)
	_fill_triangle(img, Vector2(cx - 10, by - 64), Vector2(cx + 10, by - 64), Vector2(cx, by - 88), hat_color * 1.1)
	_fill_rect(img, cx - 9, by - 66, cx + 9, by - 64, Color(0.6, 0.5, 0.15))
	_draw_star(img, cx, int(by - 87), Color(1.0, 0.95, 0.5))

	# --- Robe hem ---
	for x in range(cx - 19, cx + 20):
		var shade := 0.85 + randf() * 0.1
		_px(img, x, by - 3, robe_dark * shade)

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_mage_side(img: Image, robe: Array, skin: Color) -> void:
	var cx := 30  # Slightly left of center for side view
	var by := 92

	var robe_main: Color = robe[0]
	var robe_dark: Color = robe[2]
	var hat_color := robe_main * 0.9
	var belt_color := Color(0.45, 0.35, 0.2)
	var boot_color := Color(0.35, 0.25, 0.15)
	var eye_white := Color(0.95, 0.95, 0.95)
	var eye_pupil := Color(0.1, 0.1, 0.15)
	var outline := Color(0.12, 0.08, 0.08)

	# --- Boot (one visible in profile) ---
	_fill_ellipse(img, cx, by - 2, 6, 3, boot_color)

	# --- Robe body (side profile - narrower, asymmetric) ---
	for y in range(by - 48, by - 2):
		var progress: float = (y - (by - 48)) / 46.0
		var left_w: int = int(5 + progress * 6)
		var right_w: int = int(6 + progress * 10)  # Robe flows back
		for x in range(cx - left_w, cx + right_w + 1):
			var shade: float = 0.93 + randf() * 0.07
			_px(img, x, y, robe_main * shade)

	# --- Belt ---
	_fill_rect(img, cx - 8, by - 30, cx + 10, by - 28, belt_color)
	_fill_rect(img, cx - 1, by - 30, cx + 2, by - 28, Color(0.7, 0.6, 0.2))

	# --- One arm visible (front arm) ---
	_fill_ellipse(img, cx - 6, by - 38, 4, 7, robe_dark)
	_fill_ellipse(img, cx - 6, by - 30, 3, 3, skin)

	# --- Neck ---
	_fill_rect(img, cx - 2, by - 50, cx + 2, by - 48, skin)

	# --- Head (profile - slightly oval) ---
	_fill_ellipse(img, cx, by - 57, 7, 8, skin)

	# --- Profile features ---
	# One eye visible
	_fill_ellipse(img, cx - 4, by - 58, 2.5, 2, eye_white)
	_fill_ellipse(img, cx - 4.5, by - 58, 1.2, 1.2, eye_pupil)
	# Nose (small bump)
	_px(img, cx - 7, by - 57, skin * 1.05)
	_px(img, cx - 8, by - 57, skin * 1.05)
	_px(img, cx - 7, by - 56, skin * 1.05)
	# Eyebrow
	_fill_rect(img, cx - 6, by - 62, cx - 2, by - 61, Color(0.3, 0.2, 0.15))

	# --- Hat (profile) ---
	_fill_ellipse(img, cx, by - 63, 11, 3, hat_color)
	# Hat cone (leaning slightly)
	_fill_triangle(img, Vector2(cx - 9, by - 64), Vector2(cx + 8, by - 64), Vector2(cx + 2, by - 88), hat_color * 1.1)
	_fill_rect(img, cx - 8, by - 66, cx + 7, by - 64, Color(0.6, 0.5, 0.15))
	_draw_star(img, cx + 2, int(by - 87), Color(1.0, 0.95, 0.5))

	# --- Robe hem ---
	for x in range(cx - 10, cx + 16):
		var shade := 0.85 + randf() * 0.1
		_px(img, x, by - 3, robe_dark * shade)

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_star(img: Image, cx: int, cy: int, color: Color) -> void:
	# Simple 5-point star
	var points := [
		Vector2i(0, -3), Vector2i(1, -1), Vector2i(3, 0),
		Vector2i(1, 1), Vector2i(2, 3), Vector2i(0, 2),
		Vector2i(-2, 3), Vector2i(-1, 1), Vector2i(-3, 0),
		Vector2i(-1, -1)
	]
	var img_w := img.get_width()
	var img_h := img.get_height()
	for p in points:
		var px: int = cx + p.x
		var py: int = cy + p.y
		if px >= 0 and px < img_w and py >= 0 and py < img_h:
			img.set_pixel(px, py, color)

# ============================================
# ZOMBIE TEXTURES (64x96 pixels)
# ============================================
func generate_zombie_texture(zombie_type: String = "walker") -> ImageTexture:
	var cache_key := "zombie_%s" % zombie_type
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var size := Vector2i(64, 96)
	if zombie_type == "brute":
		size = Vector2i(80, 112)

	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var colors: Array = ZOMBIE_COLORS.get(zombie_type, ZOMBIE_COLORS["walker"])

	img.fill(Color(0, 0, 0, 0))

	var cx := size.x / 2
	var by := size.y - 6

	match zombie_type:
		"walker":
			_draw_walker_zombie(img, cx, by, colors)
		"runner":
			_draw_runner_zombie(img, cx, by, colors)
		"brute":
			_draw_brute_zombie(img, cx, by, colors)
		"mage_zombie":
			_draw_mage_zombie(img, cx, by, colors)
		"exploder":
			_draw_exploder_zombie(img, cx, by, colors)
		_:
			_draw_walker_zombie(img, cx, by, colors)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_walker_zombie(img: Image, cx: int, by: int, colors: Array) -> void:
	# Tattered clothes body
	for y in range(by - 50, by - 10):
		var width: int = 8 + int((y - (by - 50)) * 0.15)
		for x in range(cx - width, cx + width):
			if x >= 0 and x < img.get_width() and randf() > 0.1:
				var shade: float = 0.8 + randf() * 0.2
				img.set_pixel(x, y, colors[0] * shade)

	# Legs (shambling pose)
	_draw_zombie_legs(img, cx, by, colors)

	# Arms (reaching forward)
	_draw_zombie_arms(img, cx, by - 35, colors, false)

	# Head
	_draw_zombie_head(img, cx, by - 60, colors, false)

func _draw_runner_zombie(img: Image, cx: int, by: int, colors: Array) -> void:
	# Leaner body
	for y in range(by - 45, by - 10):
		var lean: int = int((y - (by - 45)) * 0.1)
		var width: int = 6 + int((y - (by - 45)) * 0.1)
		for x in range(cx - width + lean, cx + width + lean):
			if x >= 0 and x < img.get_width() and randf() > 0.05:
				img.set_pixel(x, y, colors[0] * (0.85 + randf() * 0.15))

	_draw_zombie_legs(img, cx, by, colors)
	_draw_zombie_arms(img, cx + 5, by - 32, colors, true)
	_draw_zombie_head(img, cx + 3, by - 55, colors, true)

func _draw_brute_zombie(img: Image, cx: int, by: int, colors: Array) -> void:
	# Massive body
	for y in range(by - 70, by - 15):
		var width: int = 18 + int((y - (by - 70)) * 0.2)
		for x in range(cx - width, cx + width):
			if x >= 0 and x < img.get_width():
				var shade: float = 0.75 + randf() * 0.25
				img.set_pixel(x, y, colors[0] * shade)

	# Thick legs
	for leg_offset in [-10, 10]:
		for y in range(by - 15, by):
			for dx in range(-6, 6):
				var px: int = cx + leg_offset + dx
				if px >= 0 and px < img.get_width():
					img.set_pixel(px, y, colors[2])

	# Huge arms
	for arm_side in [-1, 1]:
		for i in range(25):
			var px: int = cx + arm_side * (20 + i / 4)
			var py: int = by - 55 + i
			for dx in range(-4, 5):
				var ppx: int = px + dx
				if ppx >= 0 and ppx < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(ppx, py, colors[1])

	# Big head
	for dy in range(-15, 10):
		for dx in range(-12, 13):
			if dx * dx / 2 + dy * dy < 120:
				var px := cx + dx
				var py := by - 80 + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, colors[1])

	# Angry eyes
	img.set_pixel(cx - 5, by - 82, Color(1, 0.2, 0.1))
	img.set_pixel(cx + 5, by - 82, Color(1, 0.2, 0.1))

func _draw_mage_zombie(img: Image, cx: int, by: int, colors: Array) -> void:
	# Robed undead mage
	for y in range(by - 55, by - 5):
		var width: int = 10 + int((y - (by - 55)) * 0.25)
		var wave: int = int(sin(y * 0.2) * 2)
		for x in range(cx - width + wave, cx + width + wave):
			if x >= 0 and x < img.get_width():
				img.set_pixel(x, y, colors[0] * (0.8 + randf() * 0.2))

	# Ghostly lower half
	for y in range(by - 5, by):
		var alpha: float = 1.0 - (y - (by - 5)) / 5.0
		var width: int = 12
		for x in range(cx - width, cx + width):
			if x >= 0 and x < img.get_width():
				var c: Color = colors[0]
				c.a = alpha * 0.7
				img.set_pixel(x, y, c)

	# Skull head
	for dy in range(-12, 8):
		for dx in range(-8, 9):
			if dx * dx + dy * dy < 70:
				var px := cx + dx
				var py := by - 68 + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, Color(0.8, 0.75, 0.7))

	# Glowing eyes
	img.set_pixel(cx - 3, by - 70, Color(0.3, 1.0, 0.4))
	img.set_pixel(cx + 3, by - 70, Color(0.3, 1.0, 0.4))
	img.set_pixel(cx - 3, by - 69, Color(0.2, 0.8, 0.3))
	img.set_pixel(cx + 3, by - 69, Color(0.2, 0.8, 0.3))

	# Magic orb in hands
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if dx * dx + dy * dy < 18:
				var px := cx + dx
				var py := by - 35 + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					var dist: float = sqrt(dx * dx + dy * dy)
					var glow: Color = Color(0.5, 0.2, 0.8).lerp(Color(0.8, 0.4, 1.0), 1.0 - dist / 4.0)
					img.set_pixel(px, py, glow)

func _draw_exploder_zombie(img: Image, cx: int, by: int, colors: Array) -> void:
	# Bloated body
	for y in range(by - 50, by - 10):
		var bloat: float = sin((y - (by - 50)) / 40.0 * PI)
		var width: int = int(8 + bloat * 12)
		for x in range(cx - width, cx + width):
			if x >= 0 and x < img.get_width():
				# Pustules
				var is_pustule: bool = randf() < 0.08
				var color: Color = colors[0] if not is_pustule else Color(0.7, 0.5, 0.2)
				img.set_pixel(x, y, color * (0.8 + randf() * 0.2))

	_draw_zombie_legs(img, cx, by, colors)

	# Short stubby arms
	for arm_side in [-1, 1]:
		for i in range(8):
			var px: int = cx + arm_side * (12 + i / 3)
			var py: int = by - 35 + i
			for dx in range(-2, 3):
				var ppx: int = px + dx
				if ppx >= 0 and ppx < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(ppx, py, colors[1])

	# Bloated head
	for dy in range(-10, 6):
		for dx in range(-8, 9):
			if dx * dx + dy * dy < 60:
				var px := cx + dx
				var py := by - 58 + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, colors[1])

	# Veiny angry eyes
	img.set_pixel(cx - 3, by - 60, Color(1, 0.3, 0.1))
	img.set_pixel(cx + 3, by - 60, Color(1, 0.3, 0.1))

	# Warning glow (about to explode look)
	for y in range(by - 45, by - 20):
		for x in range(cx - 8, cx + 9):
			if x >= 0 and x < img.get_width() and randf() < 0.3:
				var existing: Color = img.get_pixel(x, y)
				img.set_pixel(x, y, existing.lerp(Color(1, 0.5, 0.1), 0.3))

func _draw_zombie_legs(img: Image, cx: int, by: int, colors: Array) -> void:
	# Shambling legs
	for leg_offset in [-5, 5]:
		var leg_forward: int = 2 if leg_offset < 0 else -2
		for y in range(by - 10, by):
			for dx in range(-3, 3):
				var px: int = cx + leg_offset + dx + leg_forward * (y - (by - 10)) / 10
				if px >= 0 and px < img.get_width():
					img.set_pixel(px, y, colors[2])

func _draw_zombie_arms(img: Image, cx: int, y: int, colors: Array, reaching: bool) -> void:
	for arm_side in [-1, 1]:
		var reach_ext: int = 8 if reaching else 0
		for i in range(15 + reach_ext):
			var px: int = cx + arm_side * (10 + i / 2)
			var py: int = y + i / 3 - reach_ext / 4
			for dx in range(-2, 3):
				var ppx: int = px + dx
				if ppx >= 0 and ppx < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(ppx, py, colors[1])

func _draw_zombie_head(img: Image, cx: int, y: int, colors: Array, tilted: bool) -> void:
	var tilt: int = 3 if tilted else 0
	for dy in range(-10, 8):
		for dx in range(-7, 8):
			if dx * dx + dy * dy < 55:
				var px := cx + dx + (dy * tilt / 10)
				var py := y + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, colors[1])

	# Dead eyes
	img.set_pixel(cx - 3 + tilt, y - 2, Color(0.8, 0.2, 0.1))
	img.set_pixel(cx + 3 + tilt, y - 2, Color(0.8, 0.2, 0.1))

	# Mouth/jaw
	for dx in range(-4, 5):
		var px := cx + dx + tilt / 2
		if px >= 0 and px < img.get_width() and y + 4 < img.get_height():
			img.set_pixel(px, y + 4, colors[2] * 0.5)

# ============================================
# TREE TEXTURES (Billboard 2D trees)
# ============================================
func generate_tree_texture(tree_type: String = "oak", view_angle: String = "front") -> ImageTexture:
	var cache_key := "tree_%s_%s" % [tree_type, view_angle]
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	var tree_data: Dictionary = TREE_COLORS.get(tree_type, TREE_COLORS["oak"])
	var trunk_color: Color = tree_data["trunk"]
	var leaves_color: Color = tree_data["leaves"]

	img.fill(Color(0, 0, 0, 0))

	var cx := 32
	var by := 124

	if view_angle == "side":
		match tree_type:
			"oak":
				_draw_oak_tree_side(img, cx, by, trunk_color, leaves_color)
			"pine":
				_draw_pine_tree_side(img, cx, by, trunk_color, leaves_color)
			"dead":
				_draw_dead_tree_side(img, cx, by, trunk_color)
			"magic":
				_draw_magic_tree_side(img, cx, by, trunk_color, leaves_color)
			"swamp":
				_draw_swamp_tree_side(img, cx, by, trunk_color, leaves_color)
			"cactus":
				_draw_cactus_side(img, cx, by, trunk_color)
			"palm":
				_draw_palm_tree_side(img, cx, by, trunk_color, leaves_color)
			"frost_pine":
				_draw_frost_pine_side(img, cx, by, trunk_color, leaves_color)
			"crystal_tree":
				_draw_crystal_tree_side(img, cx, by, trunk_color, leaves_color)
			"ember_tree":
				_draw_ember_tree_side(img, cx, by, trunk_color, leaves_color)
			"dark_oak":
				_draw_dark_oak_side(img, cx, by, trunk_color, leaves_color)
			_:
				_draw_oak_tree_side(img, cx, by, trunk_color, leaves_color)
	else:
		match tree_type:
			"oak":
				_draw_oak_tree(img, cx, by, trunk_color, leaves_color)
			"pine":
				_draw_pine_tree(img, cx, by, trunk_color, leaves_color)
			"dead":
				_draw_dead_tree(img, cx, by, trunk_color)
			"magic":
				_draw_magic_tree(img, cx, by, trunk_color, leaves_color)
			"swamp":
				_draw_swamp_tree(img, cx, by, trunk_color, leaves_color)
			"cactus":
				_draw_cactus(img, cx, by, trunk_color)
			"palm":
				_draw_palm_tree(img, cx, by, trunk_color, leaves_color)
			"frost_pine":
				_draw_frost_pine(img, cx, by, trunk_color, leaves_color)
			"crystal_tree":
				_draw_crystal_tree(img, cx, by, trunk_color, leaves_color)
			"ember_tree":
				_draw_ember_tree(img, cx, by, trunk_color, leaves_color)
			"dark_oak":
				_draw_dark_oak(img, cx, by, trunk_color, leaves_color)
			_:
				_draw_oak_tree(img, cx, by, trunk_color, leaves_color)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_oak_tree(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk
	for y in range(by - 50, by):
		var width: int = 4 + int((by - y) * 0.03)
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 64:
				var shade: float = 0.8 + randf() * 0.2
				img.set_pixel(px, y, trunk * shade)

	# Leafy canopy (multiple clusters)
	var centers := [Vector2i(cx, by - 70), Vector2i(cx - 12, by - 60), Vector2i(cx + 12, by - 60)]
	for center in centers:
		for dy in range(-25, 20):
			for dx in range(-20, 21):
				if dx * dx + dy * dy < 350 + randf() * 100:
					var px: int = center.x + dx
					var py: int = center.y + dy
					if px >= 0 and px < 64 and py >= 0 and py < 128:
						var shade: float = 0.7 + randf() * 0.3
						var existing: Color = img.get_pixel(px, py)
						if existing.a < 0.5:
							img.set_pixel(px, py, leaves * shade)

func _draw_pine_tree(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk
	for y in range(by - 35, by):
		for dx in range(-3, 4):
			var px := cx + dx
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.85 + randf() * 0.15))

	# Triangular pine layers - triangles point UP (wide at bottom, narrow at top)
	for layer in range(4):
		var layer_base_y: int = by - 45 - layer * 18  # Bottom of this layer
		var layer_height: int = 25
		var layer_width: int = 25 - layer * 4
		for y in range(layer_base_y - layer_height, layer_base_y):
			var progress: float = float(layer_base_y - y) / float(layer_height)  # 0 at bottom, 1 at top
			var width: int = int(layer_width * (1.0 - progress))  # Wide at bottom, narrow at top
			for dx in range(-width, width + 1):
				var px := cx + dx
				if px >= 0 and px < 64 and y >= 0 and y < 128:
					var shade: float = 0.75 + randf() * 0.25
					img.set_pixel(px, y, leaves * shade)

func _draw_dead_tree(img: Image, cx: int, by: int, trunk: Color) -> void:
	# Gnarled trunk
	for y in range(by - 80, by):
		var twist: int = int(sin(y * 0.1) * 3)
		var width: int = 3 + int((by - y) * 0.02)
		for dx in range(-width, width + 1):
			var px := cx + dx + twist
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.7 + randf() * 0.3))

	# Dead branches
	var branches := [
		{"start": Vector2i(cx, by - 60), "dir": Vector2i(15, -20)},
		{"start": Vector2i(cx, by - 50), "dir": Vector2i(-18, -15)},
		{"start": Vector2i(cx, by - 40), "dir": Vector2i(12, -25)},
		{"start": Vector2i(cx, by - 70), "dir": Vector2i(-10, -18)},
	]
	for branch in branches:
		_draw_branch(img, branch["start"], branch["dir"], trunk, 8)

func _draw_branch(img: Image, start: Vector2i, dir: Vector2i, color: Color, length: int) -> void:
	for i in range(length):
		var t: float = i / float(length)
		var px: int = start.x + int(dir.x * t)
		var py: int = start.y + int(dir.y * t)
		var width: int = max(1, 3 - i / 3)
		for dx in range(-width, width + 1):
			var ppx := px + dx
			if ppx >= 0 and ppx < 64 and py >= 0 and py < 128:
				img.set_pixel(ppx, py, color * (0.8 + randf() * 0.2))

func _draw_magic_tree(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Glowing trunk
	for y in range(by - 60, by):
		var width: int = 4 + int((by - y) * 0.025)
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 64:
				var glow: Color = trunk.lerp(Color(0.6, 0.3, 0.8), randf() * 0.3)
				img.set_pixel(px, y, glow)

	# Mystical canopy with sparkles
	for dy in range(-55, 10):
		for dx in range(-22, 23):
			if dx * dx + dy * dy < 400 + randf() * 150:
				var px := cx + dx
				var py := by - 75 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128:
					var is_sparkle: bool = randf() < 0.05
					var color: Color = leaves if not is_sparkle else Color(1, 0.9, 1.0)
					img.set_pixel(px, py, color * (0.7 + randf() * 0.3))

func _draw_swamp_tree(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Twisted trunk with roots
	for y in range(by - 55, by):
		var twist: int = int(sin(y * 0.15) * 4)
		var width: int = 3 + int((by - y) * 0.02) + (2 if y > by - 10 else 0)
		for dx in range(-width, width + 1):
			var px := cx + dx + twist
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.7 + randf() * 0.2))

	# Scraggly moss-covered canopy
	for dy in range(-40, 15):
		for dx in range(-18, 19):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 25 + randf() * 10:
				var px := cx + dx
				var py := by - 70 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128 and randf() > 0.15:
					# Moss-like variation
					var moss: Color = leaves.lerp(Color(0.4, 0.45, 0.3), randf() * 0.4)
					img.set_pixel(px, py, moss)

	# Hanging moss
	for x in range(cx - 15, cx + 16, 3):
		if randf() > 0.4:
			var hang_length: int = randi_range(8, 20)
			for y in range(by - 55, by - 55 + hang_length):
				if x >= 0 and x < 64 and y >= 0 and y < 128:
					img.set_pixel(x, y, Color(0.35, 0.4, 0.3, 0.8))

func _draw_cactus(img: Image, cx: int, by: int, trunk: Color) -> void:
	# Main cactus body
	for y in range(by - 70, by):
		var width: int = 6 - int(abs(y - (by - 35)) * 0.03)
		width = max(4, width)
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 64:
				var shade: float = 0.8 + randf() * 0.2
				img.set_pixel(px, y, trunk * shade)

	# Left arm
	var arm_y := by - 50
	for i in range(15):
		var px := cx - 8 - int(i * 0.3)
		var py := arm_y - i
		for dx in range(-3, 4):
			if px + dx >= 0 and px + dx < 64 and py >= 0:
				img.set_pixel(px + dx, py, trunk * (0.85 + randf() * 0.15))
	# Left arm vertical part
	for i in range(20):
		var px := cx - 12
		var py := arm_y - 15 + i
		for dx in range(-3, 4):
			if px + dx >= 0 and px + dx < 64 and py >= 0:
				img.set_pixel(px + dx, py, trunk * (0.85 + randf() * 0.15))

	# Right arm
	arm_y = by - 40
	for i in range(12):
		var px := cx + 8 + int(i * 0.2)
		var py := arm_y - i
		for dx in range(-3, 4):
			if px + dx >= 0 and px + dx < 64 and py >= 0:
				img.set_pixel(px + dx, py, trunk * (0.85 + randf() * 0.15))
	# Right arm vertical
	for i in range(25):
		var px := cx + 10
		var py := arm_y - 12 + i
		for dx in range(-3, 4):
			if px + dx >= 0 and px + dx < 64 and py >= 0 and py < 128:
				img.set_pixel(px + dx, py, trunk * (0.85 + randf() * 0.15))

func _draw_palm_tree(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Curved trunk
	for y in range(by - 80, by):
		var curve: int = int(sin((y - (by - 80)) * 0.03) * 8)
		var width: int = 3 + int((by - y) * 0.015)
		for dx in range(-width, width + 1):
			var px := cx + dx + curve
			if px >= 0 and px < 64:
				var ring: float = 0.85 + (sin(y * 0.5) * 0.1)
				img.set_pixel(px, y, trunk * ring)

	# Palm fronds (radiating leaves)
	var frond_base_x := cx + int(sin((by - 80 - (by - 80)) * 0.03) * 8)
	var frond_base_y := by - 85
	for frond in range(7):
		var angle := (frond - 3) * 0.5
		for i in range(35):
			var droop: float = i * i * 0.008
			var fx := frond_base_x + int(cos(angle) * i * 1.5)
			var fy := frond_base_y + int(sin(angle) * i * 0.5 + droop)
			var width: int = max(1, 4 - i / 10)
			for dx in range(-width, width + 1):
				if fx + dx >= 0 and fx + dx < 64 and fy >= 0 and fy < 128:
					img.set_pixel(fx + dx, fy, leaves * (0.7 + randf() * 0.3))

func _draw_frost_pine(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Icy trunk
	for y in range(by - 30, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 64:
				var ice: Color = trunk.lerp(Color(0.9, 0.95, 1.0), randf() * 0.3)
				img.set_pixel(px, y, ice)

	# Snow-covered pine layers - triangles point UP (wide at bottom, narrow at top)
	for layer in range(5):
		var layer_base_y: int = by - 40 - layer * 15  # Bottom of this layer
		var layer_height: int = 20
		var layer_width: int = 22 - layer * 3
		for y in range(layer_base_y - layer_height, layer_base_y):
			var progress: float = float(layer_base_y - y) / float(layer_height)  # 0 at bottom, 1 at top
			var width: int = int(layer_width * (1.0 - progress))  # Wide at bottom, narrow at top
			for dx in range(-width, width + 1):
				var px := cx + dx
				if px >= 0 and px < 64 and y >= 0 and y < 128:
					# Snow on top (near tip), darker underneath
					var snow_amount: float = progress * 0.7  # More snow near the top
					var color: Color = leaves.lerp(Color(1, 1, 1), snow_amount * 0.6)
					img.set_pixel(px, y, color * (0.85 + randf() * 0.15))

	# Snow cap at very top
	for dy in range(-8, 0):
		var width: int = 3 - abs(dy) / 3
		for dx in range(-width, width + 1):
			var px := cx + dx
			var py := by - 115 + dy
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, Color(1, 1, 1))

func _draw_crystal_tree(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Crystalline trunk
	for y in range(by - 50, by):
		var width: int = 3 + int((by - y) * 0.02)
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 64:
				var sparkle: Color = trunk.lerp(Color(1, 0.8, 1), randf() * 0.4)
				img.set_pixel(px, y, sparkle)

	# Magical crystal canopy with intense glow
	for dy in range(-60, 5):
		for dx in range(-20, 21):
			if dx * dx + dy * dy < 380 + randf() * 120:
				var px := cx + dx
				var py := by - 75 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128:
					var is_sparkle: bool = randf() < 0.15
					var is_bright: bool = randf() < 0.1
					var color: Color
					if is_bright:
						color = Color(1, 1, 1)  # Bright white sparkle
					elif is_sparkle:
						color = Color(1, 0.7, 1.0)  # Pink sparkle
					else:
						color = leaves * (0.8 + randf() * 0.4)
					img.set_pixel(px, py, color)

func _draw_ember_tree(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Charred trunk with glowing cracks
	for y in range(by - 70, by):
		var width: int = 4 + int((by - y) * 0.025)
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 64:
				var is_ember: bool = randf() < 0.1
				var color: Color
				if is_ember:
					color = Color(1, 0.4, 0.1)  # Glowing ember
				else:
					color = trunk * (0.7 + randf() * 0.2)
				img.set_pixel(px, y, color)

	# Flame-like canopy
	for dy in range(-45, 15):
		for dx in range(-18, 19):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 22 + randf() * 8:
				var px := cx + dx
				var py := by - 80 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128:
					var flame_t: float = dist / 25.0
					var color: Color = Color(1, 0.9, 0.3).lerp(leaves, flame_t)
					if randf() < 0.2:
						color = Color(1, 0.5, 0.1)  # Hot spots
					img.set_pixel(px, py, color * (0.7 + randf() * 0.3))

func _draw_dark_oak(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Very dark twisted trunk
	for y in range(by - 60, by):
		var twist: int = int(sin(y * 0.08) * 5)
		var width: int = 5 + int((by - y) * 0.03)
		for dx in range(-width, width + 1):
			var px := cx + dx + twist
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.6 + randf() * 0.3))

	# Very dark, dense canopy
	var centers := [Vector2i(cx, by - 75), Vector2i(cx - 14, by - 60), Vector2i(cx + 14, by - 60)]
	for center in centers:
		for dy in range(-30, 25):
			for dx in range(-22, 23):
				if dx * dx + dy * dy < 450 + randf() * 150:
					var px: int = center.x + dx
					var py: int = center.y + dy
					if px >= 0 and px < 64 and py >= 0 and py < 128:
						var existing: Color = img.get_pixel(px, py)
						if existing.a < 0.5:
							# Very dark green, almost black
							var shade: float = 0.5 + randf() * 0.4
							img.set_pixel(px, py, leaves * shade)

	# Occasional glowing eye or mushroom
	if randf() < 0.3:
		var eye_x := cx + randi_range(-10, 10)
		var eye_y := by - 50 + randi_range(-10, 10)
		if eye_x >= 0 and eye_x < 64 and eye_y >= 0 and eye_y < 128:
			img.set_pixel(eye_x, eye_y, Color(0.3, 1, 0.4))

# ============================================
# TREE SIDE-VIEW DRAWING FUNCTIONS
# ============================================
# Side views shift the trunk off-center and narrow the canopy to give depth
# when the DirectionalSprite switches angles as the camera orbits.

func _draw_oak_tree_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted left
	var tcx := cx - 8
	for y in range(by - 50, by):
		var width: int = 4 + int((by - y) * 0.03)
		for dx in range(-width, width + 1):
			var px := tcx + dx
			if px >= 0 and px < 64:
				var shade: float = 0.8 + randf() * 0.2
				img.set_pixel(px, y, trunk * shade)

	# Narrower, taller oval canopy offset to match trunk
	var canopy_cx := cx - 4
	for dy in range(-30, 20):
		for dx in range(-14, 15):
			# Oval: narrower horizontally, taller vertically
			if (dx * dx) / 180.0 + (dy * dy) / 500.0 < 1.0 + randf() * 0.15:
				var px: int = canopy_cx + dx
				var py: int = by - 70 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128:
					var shade: float = 0.7 + randf() * 0.3
					img.set_pixel(px, py, leaves * shade)

func _draw_pine_tree_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted slightly left
	var tcx := cx - 4
	for y in range(by - 35, by):
		for dx in range(-3, 4):
			var px := tcx + dx
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.85 + randf() * 0.15))

	# Narrower triangular pine layers
	for layer in range(4):
		var layer_base_y: int = by - 45 - layer * 18
		var layer_height: int = 25
		var layer_width: int = 18 - layer * 3  # Narrower than front (25 -> 18)
		for y in range(layer_base_y - layer_height, layer_base_y):
			var progress: float = float(layer_base_y - y) / float(layer_height)
			var width: int = int(layer_width * (1.0 - progress))
			for dx in range(-width, width + 1):
				var px := tcx + dx
				if px >= 0 and px < 64 and y >= 0 and y < 128:
					var shade: float = 0.75 + randf() * 0.25
					img.set_pixel(px, y, leaves * shade)

func _draw_dead_tree_side(img: Image, cx: int, by: int, trunk: Color) -> void:
	# Trunk shifted left with different twist
	var tcx := cx - 6
	for y in range(by - 80, by):
		var twist: int = int(sin(y * 0.12) * 2)
		var width: int = 3 + int((by - y) * 0.02)
		for dx in range(-width, width + 1):
			var px := tcx + dx + twist
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.7 + randf() * 0.3))

	# Branches reaching in different directions from side view
	var branches := [
		{"start": Vector2i(tcx, by - 60), "dir": Vector2i(20, -15)},
		{"start": Vector2i(tcx, by - 50), "dir": Vector2i(-12, -20)},
		{"start": Vector2i(tcx, by - 40), "dir": Vector2i(18, -10)},
		{"start": Vector2i(tcx, by - 70), "dir": Vector2i(14, -22)},
	]
	for branch in branches:
		_draw_branch(img, branch["start"], branch["dir"], trunk, 8)

func _draw_magic_tree_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted left
	var tcx := cx - 8
	for y in range(by - 60, by):
		var width: int = 4 + int((by - y) * 0.025)
		for dx in range(-width, width + 1):
			var px := tcx + dx
			if px >= 0 and px < 64:
				var glow: Color = trunk.lerp(Color(0.6, 0.3, 0.8), randf() * 0.3)
				img.set_pixel(px, y, glow)

	# Narrower mystical canopy
	var canopy_cx := cx - 4
	for dy in range(-55, 10):
		for dx in range(-16, 17):
			if dx * dx + dy * dy < 300 + randf() * 120:
				var px := canopy_cx + dx
				var py := by - 75 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128:
					var is_sparkle: bool = randf() < 0.05
					var color: Color = leaves if not is_sparkle else Color(1, 0.9, 1.0)
					img.set_pixel(px, py, color * (0.7 + randf() * 0.3))

func _draw_swamp_tree_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted left with different twist
	var tcx := cx - 6
	for y in range(by - 55, by):
		var twist: int = int(sin(y * 0.12) * 3)
		var width: int = 3 + int((by - y) * 0.02) + (2 if y > by - 10 else 0)
		for dx in range(-width, width + 1):
			var px := tcx + dx + twist
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.7 + randf() * 0.2))

	# Narrower scraggly canopy
	var canopy_cx := cx - 3
	for dy in range(-40, 15):
		for dx in range(-13, 14):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 20 + randf() * 8:
				var px := canopy_cx + dx
				var py := by - 70 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128 and randf() > 0.15:
					var moss: Color = leaves.lerp(Color(0.4, 0.45, 0.3), randf() * 0.4)
					img.set_pixel(px, py, moss)

	# Hanging moss (fewer strands from side)
	for x in range(canopy_cx - 10, canopy_cx + 11, 4):
		if randf() > 0.5:
			var hang_length: int = randi_range(6, 16)
			for y in range(by - 55, by - 55 + hang_length):
				if x >= 0 and x < 64 and y >= 0 and y < 128:
					img.set_pixel(x, y, Color(0.35, 0.4, 0.3, 0.8))

func _draw_cactus_side(img: Image, cx: int, by: int, trunk: Color) -> void:
	# Main body - narrower from side
	for y in range(by - 70, by):
		var width: int = 5 - int(abs(y - (by - 35)) * 0.03)
		width = max(3, width)
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 64:
				var shade: float = 0.8 + randf() * 0.2
				img.set_pixel(px, y, trunk * shade)

	# Only one arm visible from side (the left arm, appearing in front)
	var arm_y := by - 50
	for i in range(12):
		var px := cx - 6 - int(i * 0.2)
		var py := arm_y - i
		for dx in range(-3, 4):
			if px + dx >= 0 and px + dx < 64 and py >= 0:
				img.set_pixel(px + dx, py, trunk * (0.85 + randf() * 0.15))
	# Arm vertical part
	for i in range(18):
		var px := cx - 9
		var py := arm_y - 12 + i
		for dx in range(-3, 4):
			if px + dx >= 0 and px + dx < 64 and py >= 0 and py < 128:
				img.set_pixel(px + dx, py, trunk * (0.85 + randf() * 0.15))

func _draw_palm_tree_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Curved trunk - curve goes to one side only (more pronounced)
	for y in range(by - 80, by):
		var curve: int = int(sin((y - (by - 80)) * 0.025) * 12)
		var width: int = 3 + int((by - y) * 0.015)
		for dx in range(-width, width + 1):
			var px := cx + dx + curve
			if px >= 0 and px < 64:
				var ring: float = 0.85 + (sin(y * 0.5) * 0.1)
				img.set_pixel(px, y, trunk * ring)

	# Palm fronds from side - more stacked, less spread
	var frond_base_x := cx + int(sin((0) * 0.025) * 12)
	var frond_base_y := by - 85
	for frond in range(5):
		var angle := (frond - 2) * 0.6
		for i in range(30):
			var droop: float = i * i * 0.01
			var fx := frond_base_x + int(cos(angle) * i * 1.2)
			var fy := frond_base_y + int(sin(angle) * i * 0.4 + droop)
			var width: int = max(1, 3 - i / 10)
			for dx in range(-width, width + 1):
				if fx + dx >= 0 and fx + dx < 64 and fy >= 0 and fy < 128:
					img.set_pixel(fx + dx, fy, leaves * (0.7 + randf() * 0.3))

func _draw_frost_pine_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted slightly left
	var tcx := cx - 3
	for y in range(by - 30, by):
		for dx in range(-2, 3):
			var px := tcx + dx
			if px >= 0 and px < 64:
				var ice: Color = trunk.lerp(Color(0.9, 0.95, 1.0), randf() * 0.3)
				img.set_pixel(px, y, ice)

	# Narrower snow-covered layers
	for layer in range(5):
		var layer_base_y: int = by - 40 - layer * 15
		var layer_height: int = 20
		var layer_width: int = 16 - layer * 2  # Narrower than front (22 -> 16)
		for y in range(layer_base_y - layer_height, layer_base_y):
			var progress: float = float(layer_base_y - y) / float(layer_height)
			var width: int = int(layer_width * (1.0 - progress))
			for dx in range(-width, width + 1):
				var px := tcx + dx
				if px >= 0 and px < 64 and y >= 0 and y < 128:
					var snow_amount: float = progress * 0.7
					var color: Color = leaves.lerp(Color(1, 1, 1), snow_amount * 0.6)
					img.set_pixel(px, y, color * (0.85 + randf() * 0.15))

	# Snow cap
	for dy in range(-8, 0):
		var width: int = 2 - abs(dy) / 4
		for dx in range(-width, width + 1):
			var px := tcx + dx
			var py := by - 115 + dy
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, Color(1, 1, 1))

func _draw_crystal_tree_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted left
	var tcx := cx - 7
	for y in range(by - 50, by):
		var width: int = 3 + int((by - y) * 0.02)
		for dx in range(-width, width + 1):
			var px := tcx + dx
			if px >= 0 and px < 64:
				var sparkle: Color = trunk.lerp(Color(1, 0.8, 1), randf() * 0.4)
				img.set_pixel(px, y, sparkle)

	# Narrower crystal canopy
	var canopy_cx := cx - 3
	for dy in range(-60, 5):
		for dx in range(-15, 16):
			if dx * dx + dy * dy < 280 + randf() * 100:
				var px := canopy_cx + dx
				var py := by - 75 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128:
					var is_sparkle: bool = randf() < 0.15
					var is_bright: bool = randf() < 0.1
					var color: Color
					if is_bright:
						color = Color(1, 1, 1)
					elif is_sparkle:
						color = Color(1, 0.7, 1.0)
					else:
						color = leaves * (0.8 + randf() * 0.4)
					img.set_pixel(px, py, color)

func _draw_ember_tree_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted left
	var tcx := cx - 7
	for y in range(by - 70, by):
		var width: int = 4 + int((by - y) * 0.025)
		for dx in range(-width, width + 1):
			var px := tcx + dx
			if px >= 0 and px < 64:
				var is_ember: bool = randf() < 0.1
				var color: Color
				if is_ember:
					color = Color(1, 0.4, 0.1)
				else:
					color = trunk * (0.7 + randf() * 0.2)
				img.set_pixel(px, y, color)

	# Narrower flame canopy
	var canopy_cx := cx - 3
	for dy in range(-45, 15):
		for dx in range(-13, 14):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 18 + randf() * 6:
				var px := canopy_cx + dx
				var py := by - 80 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 128:
					var flame_t: float = dist / 20.0
					var color: Color = Color(1, 0.9, 0.3).lerp(leaves, flame_t)
					if randf() < 0.2:
						color = Color(1, 0.5, 0.1)
					img.set_pixel(px, py, color * (0.7 + randf() * 0.3))

func _draw_dark_oak_side(img: Image, cx: int, by: int, trunk: Color, leaves: Color) -> void:
	# Trunk shifted left with different twist
	var tcx := cx - 8
	for y in range(by - 60, by):
		var twist: int = int(sin(y * 0.1) * 3)
		var width: int = 5 + int((by - y) * 0.03)
		for dx in range(-width, width + 1):
			var px := tcx + dx + twist
			if px >= 0 and px < 64:
				img.set_pixel(px, y, trunk * (0.6 + randf() * 0.3))

	# Narrower, taller dark canopy
	var canopy_cx := cx - 4
	var centers := [Vector2i(canopy_cx, by - 75), Vector2i(canopy_cx - 8, by - 62)]
	for center in centers:
		for dy in range(-30, 25):
			for dx in range(-16, 17):
				if dx * dx + dy * dy < 350 + randf() * 120:
					var px: int = center.x + dx
					var py: int = center.y + dy
					if px >= 0 and px < 64 and py >= 0 and py < 128:
						var existing: Color = img.get_pixel(px, py)
						if existing.a < 0.5:
							var shade: float = 0.5 + randf() * 0.4
							img.set_pixel(px, py, leaves * shade)

	# Occasional glowing eye
	if randf() < 0.3:
		var eye_x := canopy_cx + randi_range(-8, 8)
		var eye_y := by - 50 + randi_range(-10, 10)
		if eye_x >= 0 and eye_x < 64 and eye_y >= 0 and eye_y < 128:
			img.set_pixel(eye_x, eye_y, Color(0.3, 1, 0.4))

# ============================================
# SPELL EFFECT TEXTURES
# ============================================
func generate_spell_texture(spell_type: String) -> ImageTexture:
	var cache_key := "spell_%s" % spell_type
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	match spell_type:
		"fireball":
			_draw_fireball_texture(img)
		"ice_shard":
			_draw_ice_shard_texture(img)
		"lightning":
			_draw_lightning_texture(img)
		"arcane":
			_draw_arcane_texture(img)
		"nature":
			_draw_nature_texture(img)
		"dark":
			_draw_dark_texture(img)
		"holy":
			_draw_holy_texture(img)
		_:
			_draw_arcane_texture(img)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_fireball_texture(img: Image) -> void:
	var cx := 16
	var cy := 16
	for dy in range(-14, 15):
		for dx in range(-14, 15):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 12:
				var px := cx + dx
				var py := cy + dy
				var t: float = dist / 12.0
				var color: Color = Color(1, 0.9, 0.3).lerp(Color(1, 0.3, 0.1), t)
				color.a = 1.0 - t * 0.5
				img.set_pixel(px, py, color)

func _draw_ice_shard_texture(img: Image) -> void:
	var cx := 16
	var cy := 16
	# Crystal shape
	var points := [Vector2i(0, -12), Vector2i(6, 0), Vector2i(0, 12), Vector2i(-6, 0)]
	for i in range(points.size()):
		var p1: Vector2i = points[i]
		var p2: Vector2i = points[(i + 1) % points.size()]
		for t in range(20):
			var tt: float = t / 20.0
			var px: int = cx + int(p1.x + (p2.x - p1.x) * tt)
			var py: int = cy + int(p1.y + (p2.y - p1.y) * tt)
			if px >= 0 and px < 32 and py >= 0 and py < 32:
				img.set_pixel(px, py, Color(0.7, 0.9, 1.0))
	# Fill with gradient
	for dy in range(-10, 11):
		for dx in range(-5, 6):
			var px := cx + dx
			var py := cy + dy
			if px >= 0 and px < 32 and py >= 0 and py < 32:
				var existing: Color = img.get_pixel(px, py)
				if existing.a < 0.5:
					var t: float = abs(dy) / 10.0
					img.set_pixel(px, py, Color(0.5, 0.8, 1.0, 0.8 - t * 0.5))

func _draw_lightning_texture(img: Image) -> void:
	var cx := 16
	# Lightning bolt shape
	var y := 2
	var x := cx
	while y < 30:
		var next_x: int = x + randi_range(-3, 3)
		var next_y: int = y + randi_range(2, 5)
		for yy in range(y, min(next_y, 30)):
			var xx: int = x + int((next_x - x) * (yy - y) / float(next_y - y))
			if xx >= 0 and xx < 32:
				img.set_pixel(xx, yy, Color(1, 1, 0.5))
				if xx > 0:
					img.set_pixel(xx - 1, yy, Color(0.8, 0.8, 1.0, 0.6))
				if xx < 31:
					img.set_pixel(xx + 1, yy, Color(0.8, 0.8, 1.0, 0.6))
		x = next_x
		y = next_y

func _draw_arcane_texture(img: Image) -> void:
	var cx := 16
	var cy := 16
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 10 and dist > 4:
				var angle: float = atan2(dy, dx)
				var pulse: float = sin(angle * 6) * 0.3 + 0.7
				var px := cx + dx
				var py := cy + dy
				img.set_pixel(px, py, Color(0.6, 0.3, 0.9, pulse))
	# Center orb
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if dx * dx + dy * dy < 16:
				img.set_pixel(cx + dx, cy + dy, Color(0.8, 0.5, 1.0))

func _draw_nature_texture(img: Image) -> void:
	var cx := 16
	var cy := 16
	# Leaf-like shape
	for dy in range(-12, 13):
		for dx in range(-8, 9):
			var leaf_shape: float = abs(dx) * 1.5 + abs(dy) * 0.8
			if leaf_shape < 12:
				var px := cx + dx
				var py := cy + dy
				var shade: float = 0.7 + randf() * 0.3
				img.set_pixel(px, py, Color(0.3, 0.7, 0.3) * shade)

func _draw_dark_texture(img: Image) -> void:
	var cx := 16
	var cy := 16
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 11:
				var px := cx + dx
				var py := cy + dy
				var t: float = dist / 11.0
				var alpha: float = 0.9 - t * 0.6
				var color: Color = Color(0.2, 0.1, 0.3).lerp(Color(0.4, 0.1, 0.5), t)
				color.a = alpha
				img.set_pixel(px, py, color)

func _draw_holy_texture(img: Image) -> void:
	var cx := 16
	var cy := 16
	# Glowing cross/star shape
	for i in range(-10, 11):
		if cx + i >= 0 and cx + i < 32:
			img.set_pixel(cx + i, cy, Color(1, 1, 0.8))
		if cy + i >= 0 and cy + i < 32:
			img.set_pixel(cx, cy + i, Color(1, 1, 0.8))
	# Glow around
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 7 and dist > 1:
				var px := cx + dx
				var py := cy + dy
				var existing: Color = img.get_pixel(px, py)
				if existing.a < 0.5:
					img.set_pixel(px, py, Color(1, 0.95, 0.7, 0.5 - dist * 0.05))

# ============================================
# WAND/STAFF TEXTURES
# ============================================
func generate_wand_texture(wand_type: String = "basic") -> ImageTexture:
	var cache_key := "wand_%s" % wand_type
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(16, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx := 8
	var by := 44

	match wand_type:
		"basic":
			_draw_basic_wand(img, cx, by)
		"fire":
			_draw_fire_wand(img, cx, by)
		"ice":
			_draw_ice_wand(img, cx, by)
		"lightning":
			_draw_lightning_wand(img, cx, by)
		"staff":
			_draw_staff(img, cx, by)
		_:
			_draw_basic_wand(img, cx, by)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_basic_wand(img: Image, cx: int, by: int) -> void:
	# Wooden wand
	for y in range(by - 35, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.5, 0.35, 0.2) * (0.9 + randf() * 0.1))
	# Crystal tip
	for dy in range(-8, 0):
		for dx in range(-2, 3):
			if abs(dx) + abs(dy) / 2 < 4:
				var px := cx + dx
				var py := by - 35 + dy
				if py >= 0 and px >= 0 and px < 16:
					img.set_pixel(px, py, Color(0.6, 0.7, 0.9))

func _draw_fire_wand(img: Image, cx: int, by: int) -> void:
	# Dark wood
	for y in range(by - 32, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.3, 0.15, 0.1) * (0.9 + randf() * 0.1))
	# Flame orb tip
	for dy in range(-10, 2):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 5:
				var px := cx + dx
				var py := by - 35 + dy
				if py >= 0 and px >= 0 and px < 16:
					var t: float = dist / 5.0
					img.set_pixel(px, py, Color(1, 0.6, 0.2).lerp(Color(1, 0.2, 0.1), t))

func _draw_ice_wand(img: Image, cx: int, by: int) -> void:
	# Crystal shaft
	for y in range(by - 32, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.7, 0.85, 0.95) * (0.9 + randf() * 0.1))
	# Ice crystal tip
	for dy in range(-12, 0):
		var width: int = max(1, 4 - abs(dy + 6) / 2)
		for dx in range(-width, width + 1):
			var px := cx + dx
			var py := by - 35 + dy
			if py >= 0 and px >= 0 and px < 16:
				img.set_pixel(px, py, Color(0.5, 0.8, 1.0))

func _draw_lightning_wand(img: Image, cx: int, by: int) -> void:
	# Metal shaft
	for y in range(by - 30, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.6, 0.6, 0.65) * (0.85 + randf() * 0.15))
	# Crackling orb
	for dy in range(-10, 2):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 5:
				var px := cx + dx
				var py := by - 33 + dy
				if py >= 0 and px >= 0 and px < 16:
					var is_spark: bool = randf() < 0.2
					var color: Color = Color(0.9, 0.9, 1.0) if not is_spark else Color(1, 1, 0.5)
					img.set_pixel(px, py, color)

func _draw_staff(img: Image, cx: int, by: int) -> void:
	# Long wooden staff
	for y in range(4, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.45, 0.3, 0.15) * (0.85 + randf() * 0.15))
	# Crystal head
	for dy in range(-8, 4):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 5:
				var px := cx + dx
				var py := 6 + dy
				if py >= 0 and px >= 0 and px < 16:
					img.set_pixel(px, py, Color(0.7, 0.4, 0.9) * (0.8 + randf() * 0.2))

# ============================================
# STAFF/WAND TEXTURE (16x64 pixels)
# ============================================
func generate_staff_texture(staff_type: String = "arcane") -> ImageTexture:
	var cache_key := "staff_%s" % staff_type
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(16, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx := 8
	var by := 60

	# Staff shaft (wood)
	for y in range(15, by):
		for dx in range(-1, 2):
			var px := cx + dx
			if px >= 0 and px < 16:
				var shade := 0.85 + randf() * 0.15
				img.set_pixel(px, y, Color(0.45, 0.3, 0.15) * shade)

	# Crystal/gem head based on type
	var gem_color: Color
	match staff_type:
		"fire":
			gem_color = Color(1.0, 0.3, 0.1)
		"ice":
			gem_color = Color(0.3, 0.7, 1.0)
		"lightning":
			gem_color = Color(1.0, 1.0, 0.3)
		"arcane", _:
			gem_color = Color(0.6, 0.3, 0.9)

	# Crystal shape
	for dy in range(-10, 5):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 5:
				var px := cx + dx
				var py := 12 + dy
				if py >= 0 and px >= 0 and px < 16:
					var brightness := 0.7 + (1.0 - dist / 5.0) * 0.3 + randf() * 0.1
					img.set_pixel(px, py, gem_color * brightness)

	# Crystal glow/shine
	img.set_pixel(cx - 1, 8, Color(1, 1, 1, 0.8))
	img.set_pixel(cx, 7, Color(1, 1, 1, 0.9))

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex


# ============================================
# WEAPON TEXTURES (16x48 pixels, side-view)
# ============================================
func generate_weapon_texture(weapon_type: String) -> ImageTexture:
	var cache_key := "weapon_%s" % weapon_type
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(16, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx := 8
	var by := 44

	match weapon_type:
		"stone_sword", "sword":
			_draw_weapon_sword(img, cx, by)
		"stone_axe", "axe":
			_draw_weapon_axe(img, cx, by)
		"stone_knife", "knife":
			_draw_weapon_knife(img, cx, by)
		"pickaxe", "stone_pickaxe":
			_draw_weapon_pickaxe(img, cx, by)
		"club":
			_draw_weapon_club(img, cx, by)
		"bow":
			_draw_weapon_bow(img, cx, by)
		"fire_wand", "wand_fire":
			_draw_fire_wand(img, cx, by)
		"ice_wand", "wand_ice":
			_draw_ice_wand(img, cx, by)
		"lightning_wand", "wand_lightning":
			_draw_lightning_wand(img, cx, by)
		"arcane_wand", "wand_arcane":
			_draw_basic_wand(img, cx, by)
		"nature_wand", "wand_nature":
			_draw_weapon_nature_wand(img, cx, by)
		"dark_wand", "wand_dark":
			_draw_weapon_dark_wand(img, cx, by)
		"holy_wand", "wand_holy":
			_draw_weapon_holy_wand(img, cx, by)
		_:
			# Fallback: basic wooden stick
			_draw_basic_wand(img, cx, by)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_weapon_sword(img: Image, cx: int, by: int) -> void:
	# Handle (brown)
	for y in range(by - 8, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.45, 0.3, 0.15) * (0.85 + randf() * 0.15))
	# Crossguard (dark gray)
	for dx in range(-5, 6):
		var px := cx + dx
		if px >= 0 and px < 16:
			img.set_pixel(px, by - 9, Color(0.4, 0.4, 0.45))
			img.set_pixel(px, by - 10, Color(0.45, 0.45, 0.5))
	# Blade (light gray stone)
	for y in range(4, by - 10):
		var taper: float = (by - 10.0 - y) / (by - 14.0)
		var width: int = max(1, int(3 * (1.0 - taper * 0.3)))
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 16:
				var edge: bool = abs(dx) == width
				var shade: float = 0.85 + randf() * 0.1
				if edge:
					img.set_pixel(px, y, Color(0.5, 0.5, 0.55) * shade)
				else:
					img.set_pixel(px, y, Color(0.65, 0.65, 0.7) * shade)
	# Tip (pointed)
	for dy in range(0, 4):
		var width: int = max(0, 2 - dy)
		for dx in range(-width, width + 1):
			var px := cx + dx
			var py := 3 - dy
			if py >= 0 and px >= 0 and px < 16:
				img.set_pixel(px, py, Color(0.7, 0.7, 0.75))

func _draw_weapon_axe(img: Image, cx: int, by: int) -> void:
	# Long handle (brown wood)
	for y in range(6, by):
		for dx in range(-1, 2):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.45, 0.3, 0.15) * (0.85 + randf() * 0.15))
	# Axe head (stone, right side) - triangular blade
	for y in range(6, 20):
		var progress: float = (y - 6.0) / 14.0
		var width: int
		if progress < 0.5:
			width = int(progress * 12)
		else:
			width = int((1.0 - progress) * 12)
		for dx in range(1, width + 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				var shade: float = 0.85 + randf() * 0.1
				img.set_pixel(px, y, Color(0.55, 0.55, 0.6) * shade)
	# Axe binding (darker stripe where head meets handle)
	for y in range(10, 16):
		img.set_pixel(cx, y, Color(0.3, 0.25, 0.15))
		img.set_pixel(cx + 1, y, Color(0.3, 0.25, 0.15))

func _draw_weapon_knife(img: Image, cx: int, by: int) -> void:
	# Short handle
	for y in range(by - 6, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.4, 0.28, 0.12) * (0.85 + randf() * 0.15))
	# Small crossguard
	for dx in range(-3, 4):
		var px := cx + dx
		if px >= 0 and px < 16:
			img.set_pixel(px, by - 7, Color(0.4, 0.4, 0.45))
	# Short blade
	for y in range(by - 22, by - 7):
		var taper: float = (by - 7.0 - y) / 15.0
		var width: int = max(1, int(2 * (1.0 - taper * 0.4)))
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 16:
				var shade: float = 0.85 + randf() * 0.1
				img.set_pixel(px, y, Color(0.6, 0.6, 0.65) * shade)

func _draw_weapon_pickaxe(img: Image, cx: int, by: int) -> void:
	# Long handle
	for y in range(6, by):
		for dx in range(-1, 2):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.45, 0.3, 0.15) * (0.85 + randf() * 0.15))
	# Pick head (horizontal stone piece at top)
	for dx in range(-6, 7):
		for dy in range(6, 12):
			var px := cx + dx
			if px >= 0 and px < 16:
				var shade: float = 0.85 + randf() * 0.1
				# Taper the ends to a point
				var dist_from_center: float = abs(dx) / 6.0
				if dy < 8 + int(dist_from_center * 3):
					img.set_pixel(px, dy, Color(0.55, 0.55, 0.6) * shade)

func _draw_weapon_club(img: Image, cx: int, by: int) -> void:
	# Handle (thinner wood)
	for y in range(20, by):
		for dx in range(-1, 2):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.45, 0.3, 0.15) * (0.85 + randf() * 0.15))
	# Club head (thicker wood, slightly bulging)
	for y in range(4, 22):
		var progress: float = (y - 4.0) / 18.0
		var width: int = int(2 + sin(progress * PI) * 3)
		for dx in range(-width, width + 1):
			var px := cx + dx
			if px >= 0 and px < 16:
				var shade: float = 0.8 + randf() * 0.15
				img.set_pixel(px, y, Color(0.5, 0.35, 0.2) * shade)

func _draw_weapon_bow(img: Image, cx: int, by: int) -> void:
	# Bow limb (curved wood) - draw as arc
	for y in range(4, by):
		var progress: float = (y - 4.0) / (by - 4.0)
		var curve_x: int = int(sin(progress * PI) * 5)
		# Bow limb
		for dx in range(0, 2):
			var px := cx + curve_x + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.45, 0.3, 0.15) * (0.85 + randf() * 0.15))
	# Bowstring (straight line)
	for y in range(4, by):
		var px := cx
		if px >= 0 and px < 16:
			img.set_pixel(px, y, Color(0.8, 0.75, 0.6))

func _draw_weapon_nature_wand(img: Image, cx: int, by: int) -> void:
	# Gnarled wood shaft (green-brown)
	for y in range(by - 32, by):
		var wobble: int = int(sin(y * 0.5) * 1)
		for dx in range(-2 + wobble, 3 + wobble):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.35, 0.3, 0.15) * (0.85 + randf() * 0.15))
	# Green leaf orb tip
	for dy in range(-10, 2):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 5:
				var px := cx + dx
				var py := by - 35 + dy
				if py >= 0 and px >= 0 and px < 16:
					var t: float = dist / 5.0
					img.set_pixel(px, py, Color(0.2, 0.7, 0.3).lerp(Color(0.1, 0.5, 0.2), t))

func _draw_weapon_dark_wand(img: Image, cx: int, by: int) -> void:
	# Black bone shaft
	for y in range(by - 32, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.15, 0.1, 0.15) * (0.85 + randf() * 0.15))
	# Purple-black orb
	for dy in range(-10, 2):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 5:
				var px := cx + dx
				var py := by - 35 + dy
				if py >= 0 and px >= 0 and px < 16:
					var t: float = dist / 5.0
					img.set_pixel(px, py, Color(0.4, 0.1, 0.5).lerp(Color(0.15, 0.05, 0.2), t))

func _draw_weapon_holy_wand(img: Image, cx: int, by: int) -> void:
	# White-gold shaft
	for y in range(by - 32, by):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 16:
				img.set_pixel(px, y, Color(0.85, 0.8, 0.6) * (0.85 + randf() * 0.15))
	# Golden glowing orb
	for dy in range(-10, 2):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 5:
				var px := cx + dx
				var py := by - 35 + dy
				if py >= 0 and px >= 0 and px < 16:
					var t: float = dist / 5.0
					img.set_pixel(px, py, Color(1.0, 0.95, 0.6).lerp(Color(0.9, 0.75, 0.3), t))


# ============================================
# ANIMAL TEXTURES (64x64 pixels, side-view)
# ============================================

func generate_deer_texture(view_angle: String = "side") -> ImageTexture:
	var cache_key := "animal_deer_%s" % view_angle
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var tan_body := Color(0.72, 0.55, 0.35)
	var tan_dark := Color(0.55, 0.40, 0.25)
	var belly_color := Color(0.85, 0.75, 0.60)
	var antler_color := Color(0.50, 0.38, 0.22)
	var eye_color := Color(0.1, 0.08, 0.05)
	var nose_color := Color(0.25, 0.15, 0.10)

	match view_angle:
		"side":
			_draw_deer_side(img, tan_body, tan_dark, belly_color, antler_color, eye_color, nose_color)
		"front":
			_draw_deer_front(img, tan_body, tan_dark, belly_color, antler_color, eye_color, nose_color)
		"back":
			_draw_deer_back(img, tan_body, tan_dark, belly_color, antler_color)
		_:
			_draw_deer_side(img, tan_body, tan_dark, belly_color, antler_color, eye_color, nose_color)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_deer_side(img: Image, tan_body: Color, tan_dark: Color, belly_color: Color, antler_color: Color, eye_color: Color, nose_color: Color) -> void:
	var outline := Color(0.15, 0.10, 0.06)
	# Body - long horizontal oval (facing right)
	_fill_ellipse(img, 30, 34, 16, 9, tan_body)
	# Belly lighter underside
	_fill_ellipse(img, 30, 38, 14, 5, belly_color)

	# --- Neck (angled up-right from body) ---
	_fill_triangle(img, Vector2(40, 30), Vector2(44, 30), Vector2(46, 16), tan_body * 1.02)
	_fill_triangle(img, Vector2(44, 30), Vector2(46, 16), Vector2(48, 18), tan_body * 1.02)

	# --- Head (small oval at top of neck) ---
	_fill_ellipse(img, 48, 14, 7, 5, tan_body)
	# Muzzle
	_fill_ellipse(img, 53, 16, 4, 3, tan_body * 1.05)
	# Nose
	_fill_ellipse(img, 56, 15, 1.5, 1, nose_color)
	# Eye
	_fill_ellipse(img, 50, 12, 1.5, 1.5, Color(0.95, 0.95, 0.95))
	_fill_ellipse(img, 50, 12, 0.8, 0.8, eye_color)
	# Ear (pointed, alert)
	_fill_triangle(img, Vector2(46, 10), Vector2(48, 10), Vector2(44, 4), tan_dark)

	# --- Antlers (branching up from head) ---
	_draw_line(img, 46, 9, 44, 2, antler_color)
	_draw_line(img, 44, 2, 41, 0, antler_color)
	_draw_line(img, 44, 4, 46, 1, antler_color)
	_draw_line(img, 47, 8, 49, 3, antler_color)
	_draw_line(img, 49, 3, 51, 1, antler_color)

	# --- Legs (thin, deer-like) ---
	# Front legs
	_fill_rect(img, 38, 42, 40, 56, tan_dark)
	_fill_rect(img, 42, 42, 44, 56, tan_dark)
	# Back legs
	_fill_rect(img, 18, 42, 20, 56, tan_dark)
	_fill_rect(img, 22, 42, 24, 56, tan_dark)
	# Hooves
	for lx in [38, 42, 18, 22]:
		_fill_rect(img, lx, 56, lx + 2, 58, Color(0.25, 0.18, 0.1))

	# --- Tail (short, upward) ---
	_fill_triangle(img, Vector2(13, 30), Vector2(15, 32), Vector2(10, 28), belly_color)

	# White rump patch
	_fill_ellipse(img, 15, 32, 4, 3, belly_color * 1.05)

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_deer_front(img: Image, tan_body: Color, tan_dark: Color, belly_color: Color, antler_color: Color, eye_color: Color, nose_color: Color) -> void:
	var outline := Color(0.15, 0.10, 0.06)
	var cx := 32

	# --- Body (narrower from front) ---
	_fill_ellipse(img, cx, 38, 10, 12, tan_body)
	# Belly
	_fill_ellipse(img, cx, 44, 8, 6, belly_color)

	# --- Neck ---
	_fill_rect(img, cx - 4, 22, cx + 4, 30, tan_body * 1.02)

	# --- Head (front-facing) ---
	_fill_ellipse(img, cx, 17, 7, 6, tan_body)
	# Muzzle
	_fill_ellipse(img, cx, 21, 4, 3, tan_body * 1.05)
	# Nose
	_fill_ellipse(img, cx, 20, 2, 1.2, nose_color)
	# Eyes (symmetrical)
	_fill_ellipse(img, cx - 4, 15, 1.5, 1.5, Color(0.95, 0.95, 0.95))
	_fill_ellipse(img, cx - 4, 15, 0.8, 0.8, eye_color)
	_fill_ellipse(img, cx + 4, 15, 1.5, 1.5, Color(0.95, 0.95, 0.95))
	_fill_ellipse(img, cx + 4, 15, 0.8, 0.8, eye_color)

	# --- Ears (both sides, pointed) ---
	_fill_triangle(img, Vector2(cx - 6, 13), Vector2(cx - 4, 13), Vector2(cx - 9, 6), tan_dark)
	_fill_triangle(img, Vector2(cx + 4, 13), Vector2(cx + 6, 13), Vector2(cx + 9, 6), tan_dark)

	# --- Antlers (symmetrical, both sides) ---
	# Left antler
	_draw_line(img, cx - 6, 11, cx - 10, 3, antler_color)
	_draw_line(img, cx - 10, 3, cx - 13, 1, antler_color)
	_draw_line(img, cx - 9, 5, cx - 7, 2, antler_color)
	# Right antler
	_draw_line(img, cx + 6, 11, cx + 10, 3, antler_color)
	_draw_line(img, cx + 10, 3, cx + 13, 1, antler_color)
	_draw_line(img, cx + 9, 5, cx + 7, 2, antler_color)

	# --- Legs ---
	_fill_rect(img, cx - 8, 48, cx - 5, 58, tan_dark)
	_fill_rect(img, cx + 5, 48, cx + 8, 58, tan_dark)
	# Hooves
	_fill_rect(img, cx - 8, 58, cx - 5, 60, Color(0.25, 0.18, 0.1))
	_fill_rect(img, cx + 5, 58, cx + 8, 60, Color(0.25, 0.18, 0.1))

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_deer_back(img: Image, tan_body: Color, tan_dark: Color, belly_color: Color, antler_color: Color) -> void:
	var outline := Color(0.15, 0.10, 0.06)
	var cx := 32

	# --- Body (from behind) ---
	_fill_ellipse(img, cx, 38, 10, 12, tan_body)
	# White rump patch (prominent from behind)
	_fill_ellipse(img, cx, 34, 8, 6, belly_color * 1.08)

	# --- Neck (back) ---
	_fill_rect(img, cx - 4, 22, cx + 4, 30, tan_dark * 1.1)

	# --- Back of head ---
	_fill_ellipse(img, cx, 17, 7, 6, tan_dark)
	# Ears poking up
	_fill_triangle(img, Vector2(cx - 6, 13), Vector2(cx - 4, 13), Vector2(cx - 9, 6), tan_dark * 0.9)
	_fill_triangle(img, Vector2(cx + 4, 13), Vector2(cx + 6, 13), Vector2(cx + 9, 6), tan_dark * 0.9)

	# --- Back of antlers ---
	_draw_line(img, cx - 6, 11, cx - 10, 3, antler_color)
	_draw_line(img, cx - 10, 3, cx - 13, 1, antler_color)
	_draw_line(img, cx - 9, 5, cx - 7, 2, antler_color)
	_draw_line(img, cx + 6, 11, cx + 10, 3, antler_color)
	_draw_line(img, cx + 10, 3, cx + 13, 1, antler_color)
	_draw_line(img, cx + 9, 5, cx + 7, 2, antler_color)

	# --- Tail (small white tuft) ---
	_fill_ellipse(img, cx, 27, 2, 2, belly_color * 1.1)

	# --- Legs ---
	_fill_rect(img, cx - 8, 48, cx - 5, 58, tan_dark)
	_fill_rect(img, cx + 5, 48, cx + 8, 58, tan_dark)
	_fill_rect(img, cx - 8, 58, cx - 5, 60, Color(0.25, 0.18, 0.1))
	_fill_rect(img, cx + 5, 58, cx + 8, 60, Color(0.25, 0.18, 0.1))

	_apply_outline(img, outline)
	_apply_lighting(img)

func generate_pig_texture(view_angle: String = "side") -> ImageTexture:
	var cache_key := "animal_pig_%s" % view_angle
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var pink_body := Color(0.92, 0.68, 0.65)
	var pink_dark := Color(0.80, 0.55, 0.52)
	var pink_light := Color(0.95, 0.78, 0.75)
	var snout_color := Color(0.85, 0.55, 0.50)
	var eye_color := Color(0.12, 0.08, 0.08)
	var hoof_color := Color(0.55, 0.40, 0.35)

	match view_angle:
		"side":
			_draw_pig_side(img, pink_body, pink_dark, pink_light, snout_color, eye_color, hoof_color)
		"front":
			_draw_pig_front(img, pink_body, pink_dark, pink_light, snout_color, eye_color, hoof_color)
		"back":
			_draw_pig_back(img, pink_body, pink_dark, pink_light, hoof_color)
		_:
			_draw_pig_side(img, pink_body, pink_dark, pink_light, snout_color, eye_color, hoof_color)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_pig_side(img: Image, pink_body: Color, pink_dark: Color, pink_light: Color, snout_color: Color, eye_color: Color, hoof_color: Color) -> void:
	var outline := Color(0.35, 0.18, 0.15)

	# --- Round body (facing right) ---
	_fill_ellipse(img, 28, 36, 15, 11, pink_body)
	# Belly highlight
	_fill_ellipse(img, 28, 40, 12, 6, pink_light)

	# --- Head (round, connected to body) ---
	_fill_ellipse(img, 44, 30, 9, 8, pink_body)
	# Snout (protruding)
	_fill_ellipse(img, 52, 32, 4, 3, snout_color)
	# Nostrils
	_px(img, 54, 31, pink_dark)
	_px(img, 54, 33, pink_dark)
	# Eye
	_fill_ellipse(img, 45, 28, 1.5, 1.5, Color(0.95, 0.95, 0.95))
	_fill_ellipse(img, 45, 28, 0.7, 0.7, eye_color)
	# Ear (floppy)
	_fill_triangle(img, Vector2(42, 23), Vector2(46, 23), Vector2(40, 18), pink_dark)

	# --- Stubby legs ---
	_fill_rect(img, 34, 46, 38, 54, pink_dark)
	_fill_rect(img, 40, 46, 44, 54, pink_dark)
	_fill_rect(img, 16, 46, 20, 54, pink_dark)
	_fill_rect(img, 22, 46, 26, 54, pink_dark)
	# Hooves
	for lx in [34, 40, 16, 22]:
		_fill_rect(img, lx, 54, lx + 4, 56, hoof_color)

	# --- Curly tail ---
	_draw_line(img, 13, 30, 10, 28, pink_dark)
	_draw_line(img, 10, 28, 8, 30, pink_dark)
	_draw_line(img, 8, 30, 9, 32, pink_dark)
	_px(img, 10, 32, pink_dark)

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_pig_front(img: Image, pink_body: Color, pink_dark: Color, pink_light: Color, snout_color: Color, eye_color: Color, hoof_color: Color) -> void:
	var outline := Color(0.35, 0.18, 0.15)
	var cx := 32

	# --- Round body (front view) ---
	_fill_ellipse(img, cx, 38, 12, 12, pink_body)
	# Belly
	_fill_ellipse(img, cx, 42, 10, 7, pink_light)

	# --- Round face ---
	_fill_ellipse(img, cx, 24, 10, 9, pink_body)
	# Big snout (facing viewer - circular)
	_fill_ellipse(img, cx, 28, 5, 4, snout_color)
	# Nostrils
	_fill_ellipse(img, cx - 2, 28, 1, 1, pink_dark)
	_fill_ellipse(img, cx + 2, 28, 1, 1, pink_dark)
	# Eyes
	_fill_ellipse(img, cx - 5, 22, 1.5, 1.5, Color(0.95, 0.95, 0.95))
	_fill_ellipse(img, cx - 5, 22, 0.7, 0.7, eye_color)
	_fill_ellipse(img, cx + 5, 22, 1.5, 1.5, Color(0.95, 0.95, 0.95))
	_fill_ellipse(img, cx + 5, 22, 0.7, 0.7, eye_color)
	# Ears (both sides, floppy)
	_fill_triangle(img, Vector2(cx - 8, 18), Vector2(cx - 5, 18), Vector2(cx - 11, 12), pink_dark)
	_fill_triangle(img, Vector2(cx + 5, 18), Vector2(cx + 8, 18), Vector2(cx + 11, 12), pink_dark)

	# --- Legs ---
	_fill_rect(img, cx - 10, 48, cx - 6, 56, pink_dark)
	_fill_rect(img, cx + 6, 48, cx + 10, 56, pink_dark)
	# Hooves
	_fill_rect(img, cx - 10, 56, cx - 6, 58, hoof_color)
	_fill_rect(img, cx + 6, 56, cx + 10, 58, hoof_color)

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_pig_back(img: Image, pink_body: Color, pink_dark: Color, pink_light: Color, hoof_color: Color) -> void:
	var outline := Color(0.35, 0.18, 0.15)
	var cx := 32

	# --- Round body (back view) ---
	_fill_ellipse(img, cx, 38, 12, 12, pink_body)
	# Round rear
	_fill_ellipse(img, cx, 36, 10, 9, pink_dark * 1.05)

	# --- Back of head ---
	_fill_ellipse(img, cx, 24, 9, 8, pink_body * 0.95)
	# Ears poking up
	_fill_triangle(img, Vector2(cx - 8, 18), Vector2(cx - 5, 18), Vector2(cx - 11, 12), pink_dark)
	_fill_triangle(img, Vector2(cx + 5, 18), Vector2(cx + 8, 18), Vector2(cx + 11, 12), pink_dark)

	# --- Curly tail (prominent from behind!) ---
	_draw_line(img, cx, 27, cx, 24, pink_dark)
	_draw_line(img, cx, 24, cx + 2, 22, pink_dark)
	_draw_line(img, cx + 2, 22, cx + 3, 24, pink_dark)
	_draw_line(img, cx + 3, 24, cx + 2, 26, pink_dark)
	_px(img, cx + 1, 26, pink_dark)

	# --- Legs ---
	_fill_rect(img, cx - 10, 48, cx - 6, 56, pink_dark)
	_fill_rect(img, cx + 6, 48, cx + 10, 56, pink_dark)
	_fill_rect(img, cx - 10, 56, cx - 6, 58, hoof_color)
	_fill_rect(img, cx + 6, 56, cx + 10, 58, hoof_color)

	_apply_outline(img, outline)
	_apply_lighting(img)

func generate_sheep_texture(view_angle: String = "side") -> ImageTexture:
	var cache_key := "animal_sheep_%s" % view_angle
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var wool_white := Color(0.93, 0.93, 0.90)
	var wool_light := Color(0.88, 0.87, 0.84)
	var wool_shadow := Color(0.78, 0.77, 0.73)
	var face_color := Color(0.25, 0.22, 0.20)
	var leg_color := Color(0.20, 0.18, 0.16)
	var eye_color := Color(0.08, 0.06, 0.05)
	var ear_color := Color(0.30, 0.25, 0.22)

	match view_angle:
		"side":
			_draw_sheep_side(img, wool_white, wool_light, wool_shadow, face_color, leg_color, eye_color, ear_color)
		"front":
			_draw_sheep_front(img, wool_white, wool_light, wool_shadow, face_color, leg_color, eye_color, ear_color)
		"back":
			_draw_sheep_back(img, wool_white, wool_light, wool_shadow, face_color, leg_color, ear_color)
		_:
			_draw_sheep_side(img, wool_white, wool_light, wool_shadow, face_color, leg_color, eye_color, ear_color)

	var tex := ImageTexture.create_from_image(img)
	texture_cache[cache_key] = tex
	return tex

func _draw_sheep_side(img: Image, wool_white: Color, wool_light: Color, wool_shadow: Color, face_color: Color, leg_color: Color, eye_color: Color, ear_color: Color) -> void:
	var outline := Color(0.15, 0.12, 0.10)

	# --- Fluffy wool body (large cloud shape, facing right) ---
	# Main body wool
	_fill_ellipse(img, 28, 32, 17, 12, wool_white)
	# Bumpy wool texture (overlapping circles for cloud effect)
	_fill_ellipse(img, 22, 28, 7, 5, wool_light)
	_fill_ellipse(img, 30, 26, 8, 5, wool_white * 1.02)
	_fill_ellipse(img, 36, 28, 7, 5, wool_light)
	_fill_ellipse(img, 24, 34, 6, 5, wool_shadow)
	_fill_ellipse(img, 32, 36, 7, 5, wool_shadow)
	# Top fluff
	_fill_ellipse(img, 26, 22, 5, 3, wool_white * 1.03)
	_fill_ellipse(img, 33, 22, 5, 3, wool_white * 1.03)

	# --- Dark face (sticking out right of wool) ---
	_fill_ellipse(img, 46, 28, 6, 5, face_color)
	# Muzzle
	_fill_ellipse(img, 50, 30, 3, 2.5, face_color * 1.15)
	# Eye
	_fill_ellipse(img, 47, 26, 1.2, 1.2, eye_color)
	# Eye shine
	_px(img, 47, 25, Color(0.7, 0.7, 0.7))
	# Ear
	_fill_ellipse(img, 44, 24, 3, 2, ear_color)
	# Nose
	_px(img, 52, 30, Color(0.15, 0.1, 0.08))

	# --- Dark thin legs (sticking out below wool) ---
	_fill_rect(img, 35, 43, 37, 55, leg_color)
	_fill_rect(img, 40, 43, 42, 55, leg_color)
	_fill_rect(img, 18, 43, 20, 55, leg_color)
	_fill_rect(img, 23, 43, 25, 55, leg_color)
	# Hooves
	for lx in [35, 40, 18, 23]:
		_fill_rect(img, lx, 55, lx + 2, 57, Color(0.12, 0.1, 0.08))

	# --- Small fluffy tail ---
	_fill_ellipse(img, 11, 30, 3, 3, wool_white)

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_sheep_front(img: Image, wool_white: Color, wool_light: Color, wool_shadow: Color, face_color: Color, leg_color: Color, eye_color: Color, ear_color: Color) -> void:
	var outline := Color(0.15, 0.12, 0.10)
	var cx := 32

	# --- Fluffy wool body (front view) ---
	_fill_ellipse(img, cx, 34, 14, 14, wool_white)
	# Bumpy fluff
	_fill_ellipse(img, cx - 6, 28, 6, 4, wool_light)
	_fill_ellipse(img, cx + 6, 28, 6, 4, wool_light)
	_fill_ellipse(img, cx, 24, 7, 4, wool_white * 1.02)
	_fill_ellipse(img, cx - 5, 38, 5, 4, wool_shadow)
	_fill_ellipse(img, cx + 5, 38, 5, 4, wool_shadow)

	# --- Dark face poking out of wool (front) ---
	_fill_ellipse(img, cx, 22, 6, 6, face_color)
	# Muzzle area
	_fill_ellipse(img, cx, 25, 4, 3, face_color * 1.15)
	# Eyes (both visible)
	_fill_ellipse(img, cx - 3, 20, 1.2, 1.2, eye_color)
	_px(img, cx - 3, 19, Color(0.7, 0.7, 0.7))
	_fill_ellipse(img, cx + 3, 20, 1.2, 1.2, eye_color)
	_px(img, cx + 3, 19, Color(0.7, 0.7, 0.7))
	# Nose
	_fill_ellipse(img, cx, 24, 1, 0.8, Color(0.15, 0.1, 0.08))
	# Ears (both sides)
	_fill_ellipse(img, cx - 8, 18, 3, 2, ear_color)
	_fill_ellipse(img, cx + 8, 18, 3, 2, ear_color)

	# --- Wool crown above head ---
	_fill_ellipse(img, cx, 16, 8, 4, wool_white * 1.03)

	# --- Legs ---
	_fill_rect(img, cx - 10, 46, cx - 7, 56, leg_color)
	_fill_rect(img, cx + 7, 46, cx + 10, 56, leg_color)
	_fill_rect(img, cx - 10, 56, cx - 7, 58, Color(0.12, 0.1, 0.08))
	_fill_rect(img, cx + 7, 56, cx + 10, 58, Color(0.12, 0.1, 0.08))

	_apply_outline(img, outline)
	_apply_lighting(img)

func _draw_sheep_back(img: Image, wool_white: Color, wool_light: Color, wool_shadow: Color, face_color: Color, leg_color: Color, ear_color: Color) -> void:
	var outline := Color(0.15, 0.12, 0.10)
	var cx := 32

	# --- Fluffy wool body (back view) ---
	_fill_ellipse(img, cx, 34, 14, 14, wool_white)
	# Bumpy fluff
	_fill_ellipse(img, cx - 6, 28, 6, 4, wool_light)
	_fill_ellipse(img, cx + 6, 28, 6, 4, wool_light)
	_fill_ellipse(img, cx, 26, 7, 4, wool_white * 1.02)
	_fill_ellipse(img, cx - 5, 38, 5, 4, wool_shadow)
	_fill_ellipse(img, cx + 5, 38, 5, 4, wool_shadow)
	# Top fluff
	_fill_ellipse(img, cx - 4, 22, 5, 3, wool_white * 1.03)
	_fill_ellipse(img, cx + 4, 22, 5, 3, wool_white * 1.03)

	# --- Back of dark head (small) ---
	_fill_ellipse(img, cx, 20, 5, 4, face_color)
	# Ears visible from behind
	_fill_ellipse(img, cx - 7, 18, 3, 2, ear_color)
	_fill_ellipse(img, cx + 7, 18, 3, 2, ear_color)

	# --- Fluffy tail (prominent puff) ---
	_fill_ellipse(img, cx, 22, 4, 3, wool_white * 1.05)

	# --- Legs ---
	_fill_rect(img, cx - 10, 46, cx - 7, 56, leg_color)
	_fill_rect(img, cx + 7, 46, cx + 10, 56, leg_color)
	_fill_rect(img, cx - 10, 56, cx - 7, 58, Color(0.12, 0.1, 0.08))
	_fill_rect(img, cx + 7, 56, cx + 10, 58, Color(0.12, 0.1, 0.08))

	_apply_outline(img, outline)
	_apply_lighting(img)




# Clear cache if needed
func clear_cache() -> void:
	texture_cache.clear()
