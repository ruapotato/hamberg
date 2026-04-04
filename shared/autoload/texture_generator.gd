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

func _draw_mage_front(img: Image, robe: Array, skin: Color) -> void:
	var cx := 32
	var by := 92  # Bottom of sprite

	# --- Robe skirt (bottom half, flowing) ---
	for y in range(by - 35, by):
		var progress: float = (y - (by - 35)) / 35.0
		var width: int = int(10 + progress * 10)
		var wave: int = int(sin(y * 0.4) * 1.5)
		for x in range(cx - width + wave, cx + width + wave + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				var edge_dist: float = min(abs(x - (cx - width + wave)), abs(x - (cx + width + wave)))
				var shade: float = 0.88 + randf() * 0.1
				if edge_dist <= 1:
					img.set_pixel(x, y, robe[2] * shade)
				else:
					img.set_pixel(x, y, robe[0] * shade)
		# Robe hem detail on last 2 rows
		if y >= by - 2:
			for x in range(cx - width + wave, cx + width + wave + 1):
				if x >= 0 and x < 64:
					img.set_pixel(x, y, robe[2] * 0.9)

	# --- Torso (upper body robe) ---
	for y in range(by - 55, by - 34):
		var progress: float = (y - (by - 55)) / 21.0
		var width: int = int(8 + progress * 3)
		for x in range(cx - width, cx + width + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				var shade: float = 0.9 + randf() * 0.1
				img.set_pixel(x, y, robe[0] * shade)

	# Shoulders (wider at top of torso)
	for y in range(by - 57, by - 53):
		var width := 11
		for x in range(cx - width, cx + width + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				img.set_pixel(x, y, robe[0] * 0.95)

	# Belt / sash
	for x in range(cx - 10, cx + 11):
		if x >= 0 and x < 64:
			var belt_y := by - 36
			if belt_y >= 0 and belt_y < 96:
				img.set_pixel(x, belt_y, robe[2] * 0.85)
			if belt_y + 1 < 96:
				img.set_pixel(x, belt_y + 1, robe[2] * 0.75)

	# Robe center seam
	for y in range(by - 35, by - 3):
		if cx >= 0 and cx < 64 and y >= 0 and y < 96:
			img.set_pixel(cx, y, robe[2] * 0.8)

	# --- Neck ---
	for y in range(by - 60, by - 56):
		for dx in range(-3, 4):
			var px := cx + dx
			if px >= 0 and px < 64 and y >= 0 and y < 96:
				img.set_pixel(px, y, skin * 0.95)

	# --- Head (large, ~1/4 body height = ~24px tall) ---
	var head_cy := by - 72
	var head_rx := 9  # horizontal radius
	var head_ry := 11  # vertical radius
	for dy in range(-head_ry, head_ry + 1):
		for dx in range(-head_rx, head_rx + 1):
			var nx: float = dx / float(head_rx)
			var ny: float = dy / float(head_ry)
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 96:
					var shade: float = 0.94 + randf() * 0.06
					img.set_pixel(px, py, skin * shade)

	# Eyes
	for eye_dx in [-3, 3]:
		var ex: int = cx + eye_dx
		var ey: int = head_cy - 1
		if ex >= 0 and ex < 64 and ey >= 0 and ey < 96:
			img.set_pixel(ex, ey, Color(0.1, 0.1, 0.2))
			img.set_pixel(ex, ey + 1, Color(0.1, 0.1, 0.2))
		# Eye shine
		if ex >= 0 and ex < 64 and ey - 1 >= 0:
			img.set_pixel(ex, ey - 1, Color(0.8, 0.8, 1.0, 0.8))

	# Eyebrows
	for eye_dx in [-3, 3]:
		for bx in range(-1, 2):
			var px: int = cx + eye_dx + bx
			var py: int = head_cy - 3
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				img.set_pixel(px, py, skin * 0.6)

	# Nose
	img.set_pixel(cx, head_cy + 2, skin * 0.85)
	img.set_pixel(cx, head_cy + 3, skin * 0.82)

	# Beard (wizard-style, flowing down)
	for dy in range(5, 16):
		var beard_width: int = max(0, 6 - dy / 2)
		for dx in range(-beard_width, beard_width + 1):
			var px := cx + dx
			var py := head_cy + dy
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				var shade: float = 0.9 + randf() * 0.1
				img.set_pixel(px, py, Color(0.72, 0.72, 0.77) * shade)

	# --- Wizard hat ---
	var hat_base_y := head_cy - head_ry + 1
	# Hat brim
	for dx in range(-12, 13):
		var px := cx + dx
		if px >= 0 and px < 64:
			for brim_dy in range(0, 3):
				var py := hat_base_y + brim_dy
				if py >= 0 and py < 96:
					img.set_pixel(px, py, robe[2] * 0.9)

	# Hat cone
	var hat_height := 22
	for dy in range(0, hat_height):
		var progress: float = dy / float(hat_height)
		var width: int = int(9 * (1.0 - progress))
		if width < 1:
			width = 1
		var bend: int = int(progress * progress * 5)
		for dx in range(-width, width + 1):
			var px := cx + dx + bend
			var py := hat_base_y - dy
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				var shade: float = 0.85 + (dx + width) / float(width * 2 + 1) * 0.15
				img.set_pixel(px, py, robe[1] * shade)

	# Hat tip curl
	var tip_y := hat_base_y - hat_height
	for i in range(4):
		var px := cx + int(hat_height * 0.23) + 2 + i
		var py := tip_y + i
		if px >= 0 and px < 64 and py >= 0 and py < 96:
			img.set_pixel(px, py, robe[1])

	# Star emblem on hat
	_draw_star(img, cx + 1, hat_base_y - 10, Color(1, 0.9, 0.3))

	# --- Arms (at sides, with sleeves) ---
	for arm_side in [-1, 1]:
		var arm_x: int = cx + arm_side * 12
		for i in range(18):
			var py: int = by - 54 + i
			for dx in range(-3, 4):
				var px: int = arm_x + dx
				if px >= 0 and px < 64 and py >= 0 and py < 96:
					# Sleeve widens toward bottom
					var sleeve_w: float = 3.0 + i * 0.15
					if abs(dx) <= sleeve_w:
						img.set_pixel(px, py, robe[0] * (0.88 + randf() * 0.1))
		# Hands
		for dx in range(-2, 3):
			var px: int = arm_x + dx
			var py: int = by - 35
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				img.set_pixel(px, py, skin * 0.95)
			if px >= 0 and px < 64 and py + 1 < 96:
				img.set_pixel(px, py + 1, skin * 0.95)

	# Staff/wand holder position marker (subtle)
	var marker_x := cx + 18
	var marker_y := by - 45
	if marker_x >= 0 and marker_x < 64 and marker_y >= 0 and marker_y < 96:
		img.set_pixel(marker_x, marker_y, Color(1, 1, 0, 0.5))

func _draw_mage_back(img: Image, robe: Array, skin: Color) -> void:
	var cx := 32
	var by := 92

	# --- Robe skirt (same silhouette as front) ---
	for y in range(by - 35, by):
		var progress: float = (y - (by - 35)) / 35.0
		var width: int = int(10 + progress * 10)
		var wave: int = int(sin(y * 0.4) * 1.5)
		for x in range(cx - width + wave, cx + width + wave + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				var edge_dist: float = min(abs(x - (cx - width + wave)), abs(x - (cx + width + wave)))
				var shade: float = 0.85 + randf() * 0.1
				if edge_dist <= 1:
					img.set_pixel(x, y, robe[2] * shade)
				else:
					img.set_pixel(x, y, robe[0] * shade)
		if y >= by - 2:
			for x in range(cx - width + wave, cx + width + wave + 1):
				if x >= 0 and x < 64:
					img.set_pixel(x, y, robe[2] * 0.85)

	# --- Torso back ---
	for y in range(by - 55, by - 34):
		var progress: float = (y - (by - 55)) / 21.0
		var width: int = int(8 + progress * 3)
		for x in range(cx - width, cx + width + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				var shade: float = 0.85 + randf() * 0.1
				img.set_pixel(x, y, robe[0] * shade)

	# Shoulders
	for y in range(by - 57, by - 53):
		var width := 11
		for x in range(cx - width, cx + width + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				img.set_pixel(x, y, robe[0] * 0.9)

	# Belt
	for x in range(cx - 10, cx + 11):
		if x >= 0 and x < 64:
			var belt_y := by - 36
			if belt_y >= 0 and belt_y < 96:
				img.set_pixel(x, belt_y, robe[2] * 0.8)
			if belt_y + 1 < 96:
				img.set_pixel(x, belt_y + 1, robe[2] * 0.7)

	# --- Neck (back) ---
	for y in range(by - 60, by - 56):
		for dx in range(-3, 4):
			var px := cx + dx
			if px >= 0 and px < 64 and y >= 0 and y < 96:
				img.set_pixel(px, y, skin * 0.9)

	# --- Back of head ---
	var head_cy := by - 72
	var head_rx := 9
	var head_ry := 11
	for dy in range(-head_ry, head_ry + 1):
		for dx in range(-head_rx, head_rx + 1):
			var nx: float = dx / float(head_rx)
			var ny: float = dy / float(head_ry)
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 96:
					# Hair on back of head
					var shade: float = 0.85 + randf() * 0.1
					if ny < 0.3:
						img.set_pixel(px, py, Color(0.55, 0.55, 0.60) * shade)
					else:
						img.set_pixel(px, py, skin * 0.9 * shade)

	# --- Wizard hat (back view, no star) ---
	var hat_base_y := head_cy - head_ry + 1
	for dx in range(-12, 13):
		var px := cx + dx
		if px >= 0 and px < 64:
			for brim_dy in range(0, 3):
				var py := hat_base_y + brim_dy
				if py >= 0 and py < 96:
					img.set_pixel(px, py, robe[2] * 0.85)

	var hat_height := 22
	for dy in range(0, hat_height):
		var progress: float = dy / float(hat_height)
		var width: int = int(9 * (1.0 - progress))
		if width < 1:
			width = 1
		var bend: int = int(progress * progress * 5)
		for dx in range(-width, width + 1):
			var px := cx + dx + bend
			var py := hat_base_y - dy
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				var shade: float = 0.8 + (dx + width) / float(width * 2 + 1) * 0.15
				img.set_pixel(px, py, robe[1] * shade)

	var tip_y := hat_base_y - hat_height
	for i in range(4):
		var px := cx + int(hat_height * 0.23) + 2 + i
		var py := tip_y + i
		if px >= 0 and px < 64 and py >= 0 and py < 96:
			img.set_pixel(px, py, robe[1])

	# --- Arms (back view) ---
	for arm_side in [-1, 1]:
		var arm_x: int = cx + arm_side * 12
		for i in range(18):
			var py: int = by - 54 + i
			for dx in range(-3, 4):
				var px: int = arm_x + dx
				if px >= 0 and px < 64 and py >= 0 and py < 96:
					var sleeve_w: float = 3.0 + i * 0.15
					if abs(dx) <= sleeve_w:
						img.set_pixel(px, py, robe[0] * (0.83 + randf() * 0.1))
		for dx in range(-2, 3):
			var px: int = arm_x + dx
			var py: int = by - 35
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				img.set_pixel(px, py, skin * 0.9)
			if px >= 0 and px < 64 and py + 1 < 96:
				img.set_pixel(px, py + 1, skin * 0.9)

func _draw_mage_side(img: Image, robe: Array, skin: Color) -> void:
	var cx := 30  # Slightly left of center for side view
	var by := 92

	# --- Robe skirt (side profile, narrower) ---
	for y in range(by - 35, by):
		var progress: float = (y - (by - 35)) / 35.0
		var front_w: int = int(6 + progress * 7)
		var back_w: int = int(5 + progress * 5)
		var wave: int = int(sin(y * 0.4) * 1)
		for x in range(cx - back_w + wave, cx + front_w + wave + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				var edge_dist: float = min(abs(x - (cx - back_w + wave)), abs(x - (cx + front_w + wave)))
				var shade: float = 0.88 + randf() * 0.1
				if edge_dist <= 1:
					img.set_pixel(x, y, robe[2] * shade)
				else:
					img.set_pixel(x, y, robe[0] * shade)
		if y >= by - 2:
			for x in range(cx - back_w + wave, cx + front_w + wave + 1):
				if x >= 0 and x < 64:
					img.set_pixel(x, y, robe[2] * 0.9)

	# --- Torso (side, thinner) ---
	for y in range(by - 55, by - 34):
		var progress: float = (y - (by - 55)) / 21.0
		var front_w: int = int(5 + progress * 2)
		var back_w: int = int(4 + progress * 1)
		for x in range(cx - back_w, cx + front_w + 1):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				var shade: float = 0.88 + randf() * 0.1
				img.set_pixel(x, y, robe[0] * shade)

	# Shoulders
	for y in range(by - 57, by - 53):
		for x in range(cx - 5, cx + 7):
			if x >= 0 and x < 64 and y >= 0 and y < 96:
				img.set_pixel(x, y, robe[0] * 0.92)

	# Belt
	for x in range(cx - 5, cx + 7):
		if x >= 0 and x < 64:
			var belt_y := by - 36
			if belt_y >= 0 and belt_y < 96:
				img.set_pixel(x, belt_y, robe[2] * 0.85)

	# --- Neck ---
	for y in range(by - 60, by - 56):
		for dx in range(-2, 3):
			var px := cx + dx
			if px >= 0 and px < 64 and y >= 0 and y < 96:
				img.set_pixel(px, y, skin * 0.95)

	# --- Head (side profile) ---
	var head_cy := by - 72
	var head_rx := 9
	var head_ry := 11
	for dy in range(-head_ry, head_ry + 1):
		for dx in range(-head_rx, head_rx + 1):
			var nx: float = dx / float(head_rx)
			var ny: float = dy / float(head_ry)
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 96:
					var shade: float = 0.94 + randf() * 0.06
					img.set_pixel(px, py, skin * shade)

	# Eye (one, side view)
	var ex := cx + 4
	var ey := head_cy - 1
	if ex >= 0 and ex < 64 and ey >= 0 and ey + 1 < 96:
		img.set_pixel(ex, ey, Color(0.1, 0.1, 0.2))
		img.set_pixel(ex, ey + 1, Color(0.1, 0.1, 0.2))
		if ey - 1 >= 0:
			img.set_pixel(ex, ey - 1, Color(0.8, 0.8, 1.0, 0.8))

	# Eyebrow
	for bx in range(-1, 2):
		var px := ex + bx
		var py := head_cy - 3
		if px >= 0 and px < 64 and py >= 0 and py < 96:
			img.set_pixel(px, py, skin * 0.6)

	# Nose (profile, protruding)
	for i in range(4):
		var px := cx + head_rx - 1 + i / 2
		var py := head_cy + 1 + i
		if px >= 0 and px < 64 and py >= 0 and py < 96:
			img.set_pixel(px, py, skin * 0.88)

	# Beard (side profile)
	for dy in range(5, 14):
		var beard_width: int = max(0, 5 - dy / 2)
		for dx in range(0, beard_width + 1):
			var px := cx + dx + 2
			var py := head_cy + dy
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				img.set_pixel(px, py, Color(0.72, 0.72, 0.77) * (0.9 + randf() * 0.1))

	# --- Wizard hat (side) ---
	var hat_base_y := head_cy - head_ry + 1
	for dx in range(-10, 12):
		var px := cx + dx
		if px >= 0 and px < 64:
			for brim_dy in range(0, 3):
				var py := hat_base_y + brim_dy
				if py >= 0 and py < 96:
					img.set_pixel(px, py, robe[2] * 0.9)

	var hat_height := 22
	for dy in range(0, hat_height):
		var progress: float = dy / float(hat_height)
		var width: int = int(8 * (1.0 - progress))
		if width < 1:
			width = 1
		var bend: int = int(progress * progress * 5)
		for dx in range(-width / 2, width + 1):
			var px := cx + dx + bend
			var py := hat_base_y - dy
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				var shade: float = 0.85 + randf() * 0.12
				img.set_pixel(px, py, robe[1] * shade)

	var tip_y := hat_base_y - hat_height
	for i in range(4):
		var px := cx + int(hat_height * 0.23) + 2 + i
		var py := tip_y + i
		if px >= 0 and px < 64 and py >= 0 and py < 96:
			img.set_pixel(px, py, robe[1])

	# Star on hat side
	_draw_star(img, cx + 2, hat_base_y - 10, Color(1, 0.9, 0.3))

	# --- Arm (one visible, side view) ---
	var arm_x := cx + 2
	for i in range(18):
		var py := by - 54 + i
		for dx in range(-3, 4):
			var px := arm_x + dx
			if px >= 0 and px < 64 and py >= 0 and py < 96:
				img.set_pixel(px, py, robe[0] * (0.85 + randf() * 0.1))
	# Hand
	for dx in range(-2, 3):
		var px := arm_x + dx
		var py := by - 35
		if px >= 0 and px < 64 and py >= 0 and py < 96:
			img.set_pixel(px, py, skin * 0.95)
		if px >= 0 and px < 64 and py + 1 < 96:
			img.set_pixel(px, py + 1, skin * 0.95)

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
func generate_tree_texture(tree_type: String = "oak") -> ImageTexture:
	var cache_key := "tree_%s" % tree_type
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]

	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	var tree_data: Dictionary = TREE_COLORS.get(tree_type, TREE_COLORS["oak"])
	var trunk_color: Color = tree_data["trunk"]
	var leaves_color: Color = tree_data["leaves"]

	img.fill(Color(0, 0, 0, 0))

	var cx := 32
	var by := 124

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
	# Body - horizontal oval, facing right
	for y in range(26, 45):
		for x in range(14, 48):
			var dx: float = (x - 30.0) / 14.0
			var dy: float = (y - 35.0) / 9.0
			if dx * dx + dy * dy < 1.0:
				var shade: float = 0.95 + randf() * 0.05
				if dy > 0.3:
					img.set_pixel(x, y, belly_color * shade)
				else:
					img.set_pixel(x, y, tan_body * shade)

	# Neck
	for i in range(12):
		var nx: int = 42 + i / 3
		var ny: int = 30 - i
		for dx in range(-3, 4):
			var px: int = nx + dx
			if px >= 0 and px < 64 and ny >= 0 and ny < 64:
				img.set_pixel(px, ny, tan_body * (0.93 + randf() * 0.07))
				if ny + 1 < 64:
					img.set_pixel(px, ny + 1, tan_body * (0.90 + randf() * 0.07))

	# Head
	var head_cx := 46
	var head_cy := 17
	for y in range(head_cy - 5, head_cy + 5):
		for x in range(head_cx - 4, head_cx + 6):
			var dx: float = (x - head_cx - 1) / 5.0
			var dy: float = (y - head_cy) / 4.5
			if dx * dx + dy * dy < 1.0:
				img.set_pixel(x, y, tan_body * (0.95 + randf() * 0.05))

	# Snout/nose
	img.set_pixel(head_cx + 6, head_cy + 1, nose_color)
	img.set_pixel(head_cx + 6, head_cy, nose_color)

	# Eye
	img.set_pixel(head_cx + 2, head_cy - 1, eye_color)
	img.set_pixel(head_cx + 3, head_cy - 1, eye_color)
	img.set_pixel(head_cx + 3, head_cy - 2, Color(0.9, 0.9, 1.0, 0.7))

	# Ear
	for i in range(4):
		var px: int = head_cx + 1
		var py: int = head_cy - 5 - i
		if py >= 0:
			img.set_pixel(px, py, tan_dark)
			img.set_pixel(px + 1, py, tan_dark)

	# Antlers
	for antler_side in [-1, 1]:
		var ax: int = head_cx + antler_side * 2
		for i in range(8):
			var py: int = head_cy - 6 - i
			var px: int = ax + antler_side * (i / 3)
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, antler_color)
		for i in range(4):
			var py: int = head_cy - 10 + i / 2
			var px: int = ax + antler_side * (3 + i)
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, antler_color)

	# Legs
	var leg_positions := [20, 26, 36, 42]
	for lx in leg_positions:
		for ly in range(44, 58):
			if lx >= 0 and lx < 64:
				img.set_pixel(lx, ly, tan_dark)
				img.set_pixel(lx + 1, ly, tan_dark)
		if lx >= 0 and lx < 63:
			img.set_pixel(lx, 58, Color(0.2, 0.15, 0.1))
			img.set_pixel(lx + 1, 58, Color(0.2, 0.15, 0.1))

	# Small tail
	for i in range(4):
		var px: int = 13 - i
		var py: int = 28 + i / 2
		if px >= 0 and px < 64 and py < 64:
			img.set_pixel(px, py, belly_color)
			if py + 1 < 64:
				img.set_pixel(px, py + 1, belly_color)

func _draw_deer_front(img: Image, tan_body: Color, tan_dark: Color, belly_color: Color, antler_color: Color, eye_color: Color, nose_color: Color) -> void:
	var cx := 32

	# Body - narrower front view oval
	for y in range(28, 48):
		for x in range(22, 43):
			var dx: float = (x - cx) / 9.0
			var dy: float = (y - 38.0) / 9.0
			if dx * dx + dy * dy < 1.0:
				var shade: float = 0.95 + randf() * 0.05
				if dy > 0.3:
					img.set_pixel(x, y, belly_color * shade)
				else:
					img.set_pixel(x, y, tan_body * shade)

	# Chest highlight
	for y in range(30, 38):
		for x in range(cx - 4, cx + 5):
			var dx: float = (x - cx) / 4.0
			var dy: float = (y - 34.0) / 4.0
			if dx * dx + dy * dy < 1.0:
				img.set_pixel(x, y, belly_color * (0.95 + randf() * 0.05))

	# Neck
	for y in range(22, 29):
		for dx in range(-3, 4):
			var px: int = cx + dx
			if px >= 0 and px < 64 and y >= 0:
				img.set_pixel(px, y, tan_body * (0.93 + randf() * 0.07))

	# Head - facing viewer
	var head_cy := 15
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var nx: float = dx / 6.0
			var ny: float = dy / 6.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, tan_body * (0.95 + randf() * 0.05))

	# Muzzle
	for dy in range(2, 6):
		for dx in range(-3, 4):
			var nx: float = dx / 3.0
			var ny: float = (dy - 4.0) / 2.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, belly_color * 0.95)

	# Nose
	img.set_pixel(cx - 1, head_cy + 3, nose_color)
	img.set_pixel(cx, head_cy + 3, nose_color)
	img.set_pixel(cx + 1, head_cy + 3, nose_color)

	# Eyes (both visible)
	img.set_pixel(cx - 3, head_cy - 1, eye_color)
	img.set_pixel(cx + 3, head_cy - 1, eye_color)
	img.set_pixel(cx - 3, head_cy - 2, Color(0.9, 0.9, 1.0, 0.7))
	img.set_pixel(cx + 3, head_cy - 2, Color(0.9, 0.9, 1.0, 0.7))

	# Ears (both sides, angled out)
	for i in range(4):
		for side in [-1, 1]:
			var px: int = cx + side * (6 + i)
			var py: int = head_cy - 4 - i
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, tan_dark)
				if py + 1 < 64:
					img.set_pixel(px, py + 1, tan_dark)

	# Antlers (both sides, symmetrical, going up and out)
	for antler_side in [-1, 1]:
		var ax: int = cx + antler_side * 4
		for i in range(8):
			var py: int = head_cy - 7 - i
			var px: int = ax + antler_side * (i / 2)
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, antler_color)
		for i in range(4):
			var py: int = head_cy - 11 + i / 2
			var px: int = ax + antler_side * (4 + i)
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, antler_color)

	# Front legs (two visible, closer together)
	for leg_offset in [-5, 5]:
		var lx: int = cx + leg_offset
		for ly in range(47, 58):
			if lx >= 0 and lx + 1 < 64:
				img.set_pixel(lx, ly, tan_dark)
				img.set_pixel(lx + 1, ly, tan_dark)
		if lx >= 0 and lx + 1 < 64:
			img.set_pixel(lx, 58, Color(0.2, 0.15, 0.1))
			img.set_pixel(lx + 1, 58, Color(0.2, 0.15, 0.1))

func _draw_deer_back(img: Image, tan_body: Color, tan_dark: Color, belly_color: Color, antler_color: Color) -> void:
	var cx := 32

	# Body - back view
	for y in range(28, 48):
		for x in range(22, 43):
			var dx: float = (x - cx) / 9.0
			var dy: float = (y - 38.0) / 9.0
			if dx * dx + dy * dy < 1.0:
				var shade: float = 0.92 + randf() * 0.05
				img.set_pixel(x, y, tan_body * shade)

	# Rump/white tail patch
	for dy in range(-3, 4):
		for dx in range(-4, 5):
			var nx: float = dx / 4.0
			var ny: float = dy / 3.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := 30 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, belly_color * (0.95 + randf() * 0.05))

	# Tail (white, upright)
	for i in range(6):
		var px := cx
		var py := 26 - i
		if px >= 0 and px < 64 and py >= 0:
			img.set_pixel(px, py, belly_color)
			if px + 1 < 64:
				img.set_pixel(px + 1, py, belly_color)

	# Neck (back)
	for y in range(22, 29):
		for dx in range(-3, 4):
			var px: int = cx + dx
			if px >= 0 and px < 64:
				img.set_pixel(px, y, tan_body * (0.90 + randf() * 0.07))

	# Back of head
	var head_cy := 15
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var nx: float = dx / 6.0
			var ny: float = dy / 6.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, tan_body * (0.92 + randf() * 0.05))

	# Ears (back)
	for i in range(4):
		for side in [-1, 1]:
			var px: int = cx + side * (6 + i)
			var py: int = head_cy - 4 - i
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, tan_dark)
				if py + 1 < 64:
					img.set_pixel(px, py + 1, tan_dark)

	# Antlers (from behind)
	for antler_side in [-1, 1]:
		var ax: int = cx + antler_side * 4
		for i in range(8):
			var py: int = head_cy - 7 - i
			var px: int = ax + antler_side * (i / 2)
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, antler_color)
		for i in range(4):
			var py: int = head_cy - 11 + i / 2
			var px: int = ax + antler_side * (4 + i)
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, antler_color)

	# Back legs
	for leg_offset in [-5, 5]:
		var lx: int = cx + leg_offset
		for ly in range(47, 58):
			if lx >= 0 and lx + 1 < 64:
				img.set_pixel(lx, ly, tan_dark)
				img.set_pixel(lx + 1, ly, tan_dark)
		if lx >= 0 and lx + 1 < 64:
			img.set_pixel(lx, 58, Color(0.2, 0.15, 0.1))
			img.set_pixel(lx + 1, 58, Color(0.2, 0.15, 0.1))


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
	# Body - fat round oval, facing right
	for y in range(24, 50):
		for x in range(12, 46):
			var dx: float = (x - 28.0) / 15.0
			var dy: float = (y - 36.0) / 12.0
			if dx * dx + dy * dy < 1.0:
				var shade: float = 0.95 + randf() * 0.05
				if dy > 0.4:
					img.set_pixel(x, y, pink_light * shade)
				else:
					img.set_pixel(x, y, pink_body * shade)

	# Head
	var head_cx := 46
	var head_cy := 34
	for y in range(head_cy - 7, head_cy + 7):
		for x in range(head_cx - 6, head_cx + 7):
			var dx: float = (x - head_cx) / 6.5
			var dy: float = (y - head_cy) / 6.5
			if dx * dx + dy * dy < 1.0:
				img.set_pixel(x, y, pink_body * (0.95 + randf() * 0.05))

	# Snout
	for y in range(head_cy - 2, head_cy + 3):
		for x in range(head_cx + 5, head_cx + 10):
			if x < 64:
				img.set_pixel(x, y, snout_color)
	if head_cx + 8 < 64:
		img.set_pixel(head_cx + 8, head_cy - 1, pink_dark)
		img.set_pixel(head_cx + 8, head_cy + 1, pink_dark)

	# Eye
	img.set_pixel(head_cx + 1, head_cy - 2, eye_color)
	img.set_pixel(head_cx + 2, head_cy - 2, eye_color)
	img.set_pixel(head_cx + 2, head_cy - 3, Color(0.9, 0.9, 1.0, 0.6))

	# Ear
	for i in range(5):
		var px: int = head_cx - 1 + i / 2
		var py: int = head_cy - 7 - i
		if py >= 0 and px >= 0 and px < 64:
			img.set_pixel(px, py, pink_dark)
			if px + 1 < 64:
				img.set_pixel(px + 1, py, pink_dark)

	# Legs
	var pig_leg_positions := [17, 23, 33, 39]
	for lx in pig_leg_positions:
		for ly in range(48, 56):
			if lx >= 0 and lx + 2 < 64:
				img.set_pixel(lx, ly, pink_dark)
				img.set_pixel(lx + 1, ly, pink_dark)
				img.set_pixel(lx + 2, ly, pink_dark)
		if lx >= 0 and lx + 2 < 64:
			img.set_pixel(lx, 56, hoof_color)
			img.set_pixel(lx + 1, 56, hoof_color)
			img.set_pixel(lx + 2, 56, hoof_color)

	# Curly tail
	var tail_points := [
		Vector2i(11, 30), Vector2i(10, 29), Vector2i(9, 28),
		Vector2i(8, 28), Vector2i(7, 29), Vector2i(7, 30),
		Vector2i(8, 31), Vector2i(9, 31), Vector2i(10, 30),
	]
	for p in tail_points:
		if p.x >= 0 and p.x < 64 and p.y >= 0 and p.y < 64:
			img.set_pixel(p.x, p.y, pink_dark)

func _draw_pig_front(img: Image, pink_body: Color, pink_dark: Color, pink_light: Color, snout_color: Color, eye_color: Color, hoof_color: Color) -> void:
	var cx := 32

	# Body - round, front view
	for y in range(26, 50):
		for x in range(18, 47):
			var dx: float = (x - cx) / 13.0
			var dy: float = (y - 38.0) / 11.0
			if dx * dx + dy * dy < 1.0:
				var shade: float = 0.95 + randf() * 0.05
				if dy > 0.4:
					img.set_pixel(x, y, pink_light * shade)
				else:
					img.set_pixel(x, y, pink_body * shade)

	# Head - round, facing viewer
	var head_cy := 22
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var nx: float = dx / 8.0
			var ny: float = dy / 8.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, pink_body * (0.95 + randf() * 0.05))

	# Snout (front-facing, oval)
	for dy in range(-3, 4):
		for dx in range(-4, 5):
			var nx: float = dx / 4.0
			var ny: float = dy / 3.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + 3 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, snout_color)

	# Nostrils
	img.set_pixel(cx - 2, head_cy + 3, pink_dark)
	img.set_pixel(cx + 2, head_cy + 3, pink_dark)

	# Eyes
	img.set_pixel(cx - 4, head_cy - 2, eye_color)
	img.set_pixel(cx - 3, head_cy - 2, eye_color)
	img.set_pixel(cx + 3, head_cy - 2, eye_color)
	img.set_pixel(cx + 4, head_cy - 2, eye_color)
	img.set_pixel(cx - 3, head_cy - 3, Color(0.9, 0.9, 1.0, 0.6))
	img.set_pixel(cx + 4, head_cy - 3, Color(0.9, 0.9, 1.0, 0.6))

	# Ears (both sides, flopping)
	for i in range(5):
		for side in [-1, 1]:
			var px: int = cx + side * (7 + i / 2)
			var py: int = head_cy - 6 - i
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, pink_dark)
				if px + side >= 0 and px + side < 64:
					img.set_pixel(px + side, py, pink_dark)

	# Front legs (two visible)
	for leg_offset in [-7, 7]:
		var lx: int = cx + leg_offset
		for ly in range(48, 56):
			if lx >= 0 and lx + 2 < 64:
				img.set_pixel(lx, ly, pink_dark)
				img.set_pixel(lx + 1, ly, pink_dark)
				img.set_pixel(lx + 2, ly, pink_dark)
		if lx >= 0 and lx + 2 < 64:
			img.set_pixel(lx, 56, hoof_color)
			img.set_pixel(lx + 1, 56, hoof_color)
			img.set_pixel(lx + 2, 56, hoof_color)

func _draw_pig_back(img: Image, pink_body: Color, pink_dark: Color, pink_light: Color, hoof_color: Color) -> void:
	var cx := 32

	# Body - back view
	for y in range(26, 50):
		for x in range(18, 47):
			var dx: float = (x - cx) / 13.0
			var dy: float = (y - 38.0) / 11.0
			if dx * dx + dy * dy < 1.0:
				var shade: float = 0.92 + randf() * 0.05
				img.set_pixel(x, y, pink_body * shade)

	# Back of head
	var head_cy := 22
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var nx: float = dx / 8.0
			var ny: float = dy / 8.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, pink_body * (0.92 + randf() * 0.05))

	# Ears (back view)
	for i in range(5):
		for side in [-1, 1]:
			var px: int = cx + side * (7 + i / 2)
			var py: int = head_cy - 6 - i
			if px >= 0 and px < 64 and py >= 0:
				img.set_pixel(px, py, pink_dark)
				if px + side >= 0 and px + side < 64:
					img.set_pixel(px + side, py, pink_dark)

	# Curly tail (prominent from back)
	var tail_points := [
		Vector2i(cx, 27), Vector2i(cx + 1, 26), Vector2i(cx + 2, 25),
		Vector2i(cx + 3, 25), Vector2i(cx + 4, 26), Vector2i(cx + 4, 27),
		Vector2i(cx + 3, 28), Vector2i(cx + 2, 28), Vector2i(cx + 1, 27),
		Vector2i(cx + 1, 26), Vector2i(cx + 2, 24), Vector2i(cx + 3, 24),
	]
	for p in tail_points:
		if p.x >= 0 and p.x < 64 and p.y >= 0 and p.y < 64:
			img.set_pixel(p.x, p.y, pink_dark)

	# Back legs
	for leg_offset in [-7, 7]:
		var lx: int = cx + leg_offset
		for ly in range(48, 56):
			if lx >= 0 and lx + 2 < 64:
				img.set_pixel(lx, ly, pink_dark)
				img.set_pixel(lx + 1, ly, pink_dark)
				img.set_pixel(lx + 2, ly, pink_dark)
		if lx >= 0 and lx + 2 < 64:
			img.set_pixel(lx, 56, hoof_color)
			img.set_pixel(lx + 1, 56, hoof_color)
			img.set_pixel(lx + 2, 56, hoof_color)


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
	# Wool body - large puffy cloud shape, facing right
	for y in range(18, 48):
		for x in range(10, 48):
			var dx: float = (x - 28.0) / 17.0
			var dy: float = (y - 32.0) / 13.0
			if dx * dx + dy * dy < 1.0:
				var bump: float = sin(x * 1.5) * cos(y * 1.3) * 0.15
				var dist: float = dx * dx + dy * dy
				var shade: float = 0.92 + randf() * 0.08
				if dist + bump > 0.7:
					img.set_pixel(x, y, wool_shadow * shade)
				elif randf() < 0.3:
					img.set_pixel(x, y, wool_light * shade)
				else:
					img.set_pixel(x, y, wool_white * shade)

	# Extra wool bumps on top
	var bump_centers := [
		Vector2i(20, 19), Vector2i(27, 17), Vector2i(34, 18),
		Vector2i(17, 21), Vector2i(39, 20), Vector2i(24, 18),
		Vector2i(31, 17), Vector2i(22, 20), Vector2i(36, 19),
	]
	for bc in bump_centers:
		for dy in range(-3, 3):
			for dx in range(-3, 3):
				if dx * dx + dy * dy < 7:
					var px: int = bc.x + dx
					var py: int = bc.y + dy
					if px >= 0 and px < 64 and py >= 0 and py < 64:
						var shade: float = 0.93 + randf() * 0.07
						if randf() < 0.4:
							img.set_pixel(px, py, wool_light * shade)
						else:
							img.set_pixel(px, py, wool_white * shade)

	# Face/head
	var face_cx := 48
	var face_cy := 30
	for y in range(face_cy - 6, face_cy + 6):
		for x in range(face_cx - 4, face_cx + 6):
			var dx: float = (x - face_cx) / 5.0
			var dy: float = (y - face_cy) / 5.5
			if dx * dx + dy * dy < 1.0:
				var shade: float = 0.92 + randf() * 0.08
				img.set_pixel(x, y, face_color * shade)

	# Muzzle
	for y in range(face_cy + 2, face_cy + 5):
		for x in range(face_cx + 1, face_cx + 5):
			if x < 64 and y < 64:
				var dx: float = (x - (face_cx + 3)) / 2.5
				var dy: float = (y - (face_cy + 3)) / 2.0
				if dx * dx + dy * dy < 1.0:
					img.set_pixel(x, y, ear_color)

	# Eyes
	img.set_pixel(face_cx + 1, face_cy - 2, eye_color)
	img.set_pixel(face_cx + 2, face_cy - 2, eye_color)
	img.set_pixel(face_cx + 2, face_cy - 3, Color(0.8, 0.8, 0.9, 0.6))

	# Ears
	for i in range(3):
		var py: int = face_cy - 4 + i
		var px: int = face_cx + 5 + i
		if px < 64 and py >= 0:
			img.set_pixel(px, py, ear_color)
			if py + 1 < 64:
				img.set_pixel(px, py + 1, ear_color)
	for i in range(3):
		var py: int = face_cy - 5 + i
		var px: int = face_cx - 5 - i
		if px >= 0 and py >= 0:
			img.set_pixel(px, py, ear_color)

	# Legs
	var sheep_leg_positions := [16, 22, 34, 40]
	for lx in sheep_leg_positions:
		for ly in range(46, 58):
			if lx >= 0 and lx + 1 < 64:
				img.set_pixel(lx, ly, leg_color)
				img.set_pixel(lx + 1, ly, leg_color)
		if lx >= 0 and lx + 1 < 64:
			img.set_pixel(lx, 58, Color(0.12, 0.10, 0.08))
			img.set_pixel(lx + 1, 58, Color(0.12, 0.10, 0.08))

	# Small woolly tail
	for dy in range(-2, 3):
		for dx in range(-2, 2):
			if dx * dx + dy * dy < 5:
				var px: int = 9 + dx
				var py: int = 28 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, wool_white * (0.90 + randf() * 0.10))

func _draw_sheep_front(img: Image, wool_white: Color, wool_light: Color, wool_shadow: Color, face_color: Color, leg_color: Color, eye_color: Color, ear_color: Color) -> void:
	var cx := 32

	# Wool body - round puffy front view
	for y in range(20, 50):
		for x in range(14, 51):
			var dx: float = (x - cx) / 16.0
			var dy: float = (y - 34.0) / 14.0
			if dx * dx + dy * dy < 1.0:
				var bump: float = sin(x * 1.5) * cos(y * 1.3) * 0.15
				var dist: float = dx * dx + dy * dy
				var shade: float = 0.92 + randf() * 0.08
				if dist + bump > 0.7:
					img.set_pixel(x, y, wool_shadow * shade)
				elif randf() < 0.3:
					img.set_pixel(x, y, wool_light * shade)
				else:
					img.set_pixel(x, y, wool_white * shade)

	# Wool bumps on top
	var bump_centers := [
		Vector2i(24, 20), Vector2i(32, 18), Vector2i(40, 20),
		Vector2i(28, 19), Vector2i(36, 19),
	]
	for bc in bump_centers:
		for dy in range(-3, 3):
			for dx in range(-3, 3):
				if dx * dx + dy * dy < 7:
					var px: int = bc.x + dx
					var py: int = bc.y + dy
					if px >= 0 and px < 64 and py >= 0 and py < 64:
						var shade: float = 0.93 + randf() * 0.07
						if randf() < 0.4:
							img.set_pixel(px, py, wool_light * shade)
						else:
							img.set_pixel(px, py, wool_white * shade)

	# Face - dark, centered in wool
	var face_cy := 30
	for dy in range(-7, 8):
		for dx in range(-6, 7):
			var nx: float = dx / 6.0
			var ny: float = dy / 7.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := face_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, face_color * (0.92 + randf() * 0.08))

	# Muzzle
	for dy in range(3, 7):
		for dx in range(-3, 4):
			var nx: float = dx / 3.0
			var ny: float = (dy - 5.0) / 2.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := face_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, ear_color)

	# Eyes (both)
	img.set_pixel(cx - 3, face_cy - 2, eye_color)
	img.set_pixel(cx - 2, face_cy - 2, eye_color)
	img.set_pixel(cx + 2, face_cy - 2, eye_color)
	img.set_pixel(cx + 3, face_cy - 2, eye_color)
	img.set_pixel(cx - 2, face_cy - 3, Color(0.8, 0.8, 0.9, 0.6))
	img.set_pixel(cx + 3, face_cy - 3, Color(0.8, 0.8, 0.9, 0.6))

	# Ears (both sides)
	for i in range(3):
		for side in [-1, 1]:
			var px: int = cx + side * (8 + i)
			var py: int = face_cy - 3 + i
			if px >= 0 and px < 64 and py >= 0 and py < 64:
				img.set_pixel(px, py, ear_color)
				if py + 1 < 64:
					img.set_pixel(px, py + 1, ear_color)

	# Legs (two visible)
	for leg_offset in [-6, 6]:
		var lx: int = cx + leg_offset
		for ly in range(48, 58):
			if lx >= 0 and lx + 1 < 64:
				img.set_pixel(lx, ly, leg_color)
				img.set_pixel(lx + 1, ly, leg_color)
		if lx >= 0 and lx + 1 < 64:
			img.set_pixel(lx, 58, Color(0.12, 0.10, 0.08))
			img.set_pixel(lx + 1, 58, Color(0.12, 0.10, 0.08))

func _draw_sheep_back(img: Image, wool_white: Color, wool_light: Color, wool_shadow: Color, face_color: Color, leg_color: Color, ear_color: Color) -> void:
	var cx := 32

	# Wool body - back view (same puffy shape)
	for y in range(20, 50):
		for x in range(14, 51):
			var dx: float = (x - cx) / 16.0
			var dy: float = (y - 34.0) / 14.0
			if dx * dx + dy * dy < 1.0:
				var bump: float = sin(x * 1.5) * cos(y * 1.3) * 0.15
				var dist: float = dx * dx + dy * dy
				var shade: float = 0.90 + randf() * 0.08
				if dist + bump > 0.7:
					img.set_pixel(x, y, wool_shadow * shade)
				elif randf() < 0.3:
					img.set_pixel(x, y, wool_light * shade)
				else:
					img.set_pixel(x, y, wool_white * shade)

	# Wool bumps on top (back)
	var bump_centers := [
		Vector2i(24, 20), Vector2i(32, 18), Vector2i(40, 20),
		Vector2i(28, 19), Vector2i(36, 19),
	]
	for bc in bump_centers:
		for dy in range(-3, 3):
			for dx in range(-3, 3):
				if dx * dx + dy * dy < 7:
					var px: int = bc.x + dx
					var py: int = bc.y + dy
					if px >= 0 and px < 64 and py >= 0 and py < 64:
						var shade: float = 0.93 + randf() * 0.07
						if randf() < 0.4:
							img.set_pixel(px, py, wool_light * shade)
						else:
							img.set_pixel(px, py, wool_white * shade)

	# Back of head (dark, peeking above wool)
	var head_cy := 24
	for dy in range(-5, 4):
		for dx in range(-5, 6):
			var nx: float = dx / 5.0
			var ny: float = dy / 4.0
			if nx * nx + ny * ny < 1.0:
				var px := cx + dx
				var py := head_cy + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, face_color * (0.90 + randf() * 0.08))

	# Ears (back view, both sides)
	for i in range(3):
		for side in [-1, 1]:
			var px: int = cx + side * (7 + i)
			var py: int = head_cy - 1 + i
			if px >= 0 and px < 64 and py >= 0 and py < 64:
				img.set_pixel(px, py, ear_color)
				if py + 1 < 64:
					img.set_pixel(px, py + 1, ear_color)

	# Woolly tail (prominent from back)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx * dx + dy * dy < 10:
				var px: int = cx + dx
				var py: int = 28 + dy
				if px >= 0 and px < 64 and py >= 0 and py < 64:
					img.set_pixel(px, py, wool_white * (0.92 + randf() * 0.08))

	# Legs (two visible from back)
	for leg_offset in [-6, 6]:
		var lx: int = cx + leg_offset
		for ly in range(48, 58):
			if lx >= 0 and lx + 1 < 64:
				img.set_pixel(lx, ly, leg_color)
				img.set_pixel(lx + 1, ly, leg_color)
		if lx >= 0 and lx + 1 < 64:
			img.set_pixel(lx, 58, Color(0.12, 0.10, 0.08))
			img.set_pixel(lx + 1, 58, Color(0.12, 0.10, 0.08))


# Clear cache if needed
func clear_cache() -> void:
	texture_cache.clear()
