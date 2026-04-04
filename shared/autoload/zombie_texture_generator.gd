extends Node
## Generates procedural pixel art textures for different zombie types
## Copied from Zombies-vs-Humans for consistent art style

# Cached textures so we don't regenerate every spawn
static var texture_cache: Dictionary = {}

static func get_zombie_texture(zombie_type: String, view_angle: String = "front") -> ImageTexture:
	var cache_key := "%s_%s" % [zombie_type, view_angle]
	if cache_key in texture_cache:
		return texture_cache[cache_key]

	var tex := _generate_texture(zombie_type, view_angle)
	texture_cache[cache_key] = tex
	return tex


static func _generate_texture(zombie_type: String, view_angle: String) -> ImageTexture:
	match zombie_type:
		"runner":
			return _generate_runner(view_angle)
		"brute":
			return _generate_brute(view_angle)
		"leaper":
			return _generate_leaper(view_angle)
		"tank":
			return _generate_tank(view_angle)
		"mage", "mage_zombie":
			return _generate_mage_zombie(view_angle)
		"exploder":
			return _generate_exploder(view_angle)
		_:
			return _generate_walker(view_angle)


# ==============================================
# WALKER
# ==============================================

static func _generate_walker(view_angle: String = "front") -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.4, 0.55, 0.35)
	var dark := Color(0.3, 0.42, 0.28)
	var eye := Color(0.9, 0.2, 0.2)

	match view_angle:
		"side":
			# Head (shifted right to show profile)
			_draw_circle(img, 36, 16, 12, body)
			# One eye visible
			_draw_circle(img, 40, 14, 3, dark)
			_draw_circle(img, 40, 14, 2, eye)
			# Mouth (shorter, profile)
			for x in range(38, 48):
				var y_off := (x % 3)
				_safe_pixel(img, x, 22 + y_off, dark)
				_safe_pixel(img, x, 23 + y_off, dark)
			# Body (narrower, off-center)
			_draw_body(img, 34, 28, 70, 11, body, dark)
			# Far-side shading
			_draw_body_shading(img, 34, 28, 70, 11, dark, -1)
			# One arm visible
			_draw_arm(img, 40, 32, 60, 0.1, 4, dark)
			# One leg visible
			_draw_leg(img, 36, 68, 94, 0.05, 5, dark)
		"back":
			# Head (no face details)
			_draw_circle(img, 32, 16, 12, body)
			# Back of skull shading
			_draw_circle(img, 32, 16, 8, dark.lerp(body, 0.5))
			# Body (slightly darker)
			_draw_body(img, 32, 28, 70, 18, body.darkened(0.1), dark)
			# Arms (reversed)
			_draw_arm(img, 49, 32, 60, 0.15, 4, dark)
			_draw_arm(img, 14, 32, 58, -0.2, 4, dark)
			# Legs (no knee detail)
			_draw_leg(img, 24, 68, 94, 0.05, 5, dark)
			_draw_leg(img, 40, 68, 92, -0.05, 5, dark)
		_:  # "front"
			# Head
			_draw_circle(img, 32, 16, 12, body)
			# Eyes
			_draw_circle(img, 26, 14, 3, dark)
			_draw_circle(img, 38, 14, 3, dark)
			_draw_circle(img, 26, 14, 2, eye)
			_draw_circle(img, 38, 14, 2, eye)
			# Mouth
			for x in range(24, 41):
				var y_off := (x % 3)
				_safe_pixel(img, x, 22 + y_off, dark)
				_safe_pixel(img, x, 23 + y_off, dark)
			# Body
			_draw_body(img, 32, 28, 70, 18, body, dark)
			# Arms
			_draw_arm(img, 14, 32, 60, 0.2, 4, dark)
			_draw_arm(img, 49, 32, 58, -0.15, 4, dark)
			# Legs
			_draw_leg(img, 24, 68, 94, 0.1, 5, dark)
			_draw_leg(img, 40, 68, 92, -0.05, 5, dark)

	_apply_outline(img, Color(0.1, 0.1, 0.1))
	_apply_lighting(img)
	return ImageTexture.create_from_image(img)


# ==============================================
# RUNNER
# ==============================================

static func _generate_runner(view_angle: String = "front") -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.55, 0.35, 0.35)
	var dark := Color(0.42, 0.28, 0.28)
	var eye := Color(1.0, 0.3, 0.1)

	match view_angle:
		"side":
			# Lean head in profile
			_draw_circle(img, 36, 14, 10, body)
			# One eye
			_draw_circle(img, 40, 12, 3, dark)
			_draw_circle(img, 40, 12, 2, eye)
			# Snarling mouth (profile)
			for x in range(38, 46):
				_safe_pixel(img, x, 19, dark)
				_safe_pixel(img, x, 20, dark)
				if x % 2 == 0:
					_safe_pixel(img, x, 21, Color.WHITE)
			# Thin body (narrower, profile)
			for y in range(24, 68):
				var width: int = 7 - int(abs(y - 42) * 0.06)
				var lean: int = int((y - 24) * 0.1)
				for x in range(34 - width + lean, 34 + width + lean):
					if (x + y) % 5 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# One arm (reaching forward)
			_draw_arm(img, 38, 28, 62, 0.3, 3, dark)
			# One leg
			_draw_leg(img, 34, 66, 92, 0.1, 4, dark)
		"back":
			# Head (no face)
			_draw_circle(img, 32, 14, 10, body)
			_draw_circle(img, 32, 14, 6, dark.lerp(body, 0.5))
			# Thin body (back)
			for y in range(24, 68):
				var width: int = 12 - int(abs(y - 42) * 0.1)
				var lean: int = int((y - 24) * 0.1)
				for x in range(32 - width + lean, 32 + width + lean):
					if (x + y) % 5 != 0:
						_safe_pixel(img, x, y, body.darkened(0.1))
					else:
						_safe_pixel(img, x, y, dark)
			# Arms reversed
			_draw_arm(img, 46, 28, 60, -0.3, 3, dark)
			_draw_arm(img, 18, 28, 62, 0.25, 3, dark)
			# Legs
			_draw_leg(img, 26, 66, 92, 0.1, 4, dark)
			_draw_leg(img, 38, 66, 94, -0.1, 4, dark)
		_:  # "front"
			# Smaller, leaner head
			_draw_circle(img, 32, 14, 10, body)
			# Angry eyes
			_draw_circle(img, 27, 12, 3, dark)
			_draw_circle(img, 37, 12, 3, dark)
			_draw_circle(img, 27, 12, 2, eye)
			_draw_circle(img, 37, 12, 2, eye)
			# Snarling mouth
			for x in range(26, 39):
				_safe_pixel(img, x, 19, dark)
				_safe_pixel(img, x, 20, dark)
				if x % 2 == 0:
					_safe_pixel(img, x, 21, Color.WHITE)
			# Thin body (leaning forward)
			for y in range(24, 68):
				var width: int = 12 - int(abs(y - 42) * 0.1)
				var lean: int = int((y - 24) * 0.1)
				for x in range(32 - width + lean, 32 + width + lean):
					if (x + y) % 5 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Long arms
			_draw_arm(img, 18, 28, 62, 0.3, 3, dark)
			_draw_arm(img, 46, 28, 60, -0.25, 3, dark)
			# Athletic legs
			_draw_leg(img, 26, 66, 92, 0.15, 4, dark)
			_draw_leg(img, 38, 66, 94, -0.1, 4, dark)

	_apply_outline(img, Color(0.1, 0.1, 0.1))
	_apply_lighting(img)
	return ImageTexture.create_from_image(img)


# ==============================================
# BRUTE
# ==============================================

static func _generate_brute(view_angle: String = "front") -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.45, 0.4, 0.35)
	var dark := Color(0.32, 0.28, 0.25)
	var eye := Color(0.8, 0.5, 0.1)

	match view_angle:
		"side":
			# Big head in profile
			_draw_circle(img, 36, 18, 14, body)
			# One eye
			_draw_circle(img, 42, 16, 3, dark)
			_draw_circle(img, 42, 16, 2, eye)
			# Heavy brow (profile)
			for x in range(30, 48):
				_safe_pixel(img, x, 12, dark)
				_safe_pixel(img, x, 13, dark)
			# Massive body (narrower profile ~60%)
			for y in range(30, 72):
				var width: int = 13 - int(abs(y - 48) * 0.07)
				for x in range(34 - width, 34 + width):
					if (x + y) % 4 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Far-side shading
			_draw_body_shading(img, 34, 30, 72, 13, dark, -1)
			# One thick arm
			_draw_arm(img, 44, 34, 65, 0.05, 7, dark)
			# One thick leg
			_draw_leg(img, 34, 70, 95, 0.03, 7, dark)
		"back":
			# Big head (no face)
			_draw_circle(img, 32, 18, 14, body)
			_draw_circle(img, 32, 18, 10, dark.lerp(body, 0.5))
			# Heavy brow visible from back too
			for x in range(22, 42):
				_safe_pixel(img, x, 12, dark)
				_safe_pixel(img, x, 13, dark)
			# Massive body (back, darker)
			for y in range(30, 72):
				var width: int = 22 - int(abs(y - 48) * 0.12)
				for x in range(32 - width, 32 + width):
					if (x + y) % 4 != 0:
						_safe_pixel(img, x, y, body.darkened(0.1))
					else:
						_safe_pixel(img, x, y, dark)
			# Arms reversed
			_draw_arm(img, 55, 34, 63, -0.1, 7, dark)
			_draw_arm(img, 8, 34, 65, 0.1, 7, dark)
			# Thick legs
			_draw_leg(img, 22, 70, 95, 0.05, 7, dark)
			_draw_leg(img, 42, 70, 95, -0.05, 7, dark)
		_:  # "front"
			# Big head
			_draw_circle(img, 32, 18, 14, body)
			# Small angry eyes
			_draw_circle(img, 26, 16, 3, dark)
			_draw_circle(img, 38, 16, 3, dark)
			_draw_circle(img, 26, 16, 2, eye)
			_draw_circle(img, 38, 16, 2, eye)
			# Heavy brow
			for x in range(22, 42):
				_safe_pixel(img, x, 12, dark)
				_safe_pixel(img, x, 13, dark)
			# Massive body
			for y in range(30, 72):
				var width: int = 22 - int(abs(y - 48) * 0.12)
				for x in range(32 - width, 32 + width):
					if (x + y) % 4 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Thick arms
			_draw_arm(img, 8, 34, 65, 0.1, 7, dark)
			_draw_arm(img, 55, 34, 63, -0.1, 7, dark)
			# Thick legs
			_draw_leg(img, 22, 70, 95, 0.05, 7, dark)
			_draw_leg(img, 42, 70, 95, -0.05, 7, dark)

	_apply_outline(img, Color(0.1, 0.1, 0.1))
	_apply_lighting(img)
	return ImageTexture.create_from_image(img)


# ==============================================
# LEAPER
# ==============================================

static func _generate_leaper(view_angle: String = "front") -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.5, 0.35, 0.4)
	var dark := Color(0.38, 0.25, 0.3)
	var eye := Color(0.2, 1.0, 0.3)

	match view_angle:
		"side":
			# Hunched head (profile)
			_draw_circle(img, 40, 22, 11, body)
			# One creepy eye
			_draw_circle(img, 46, 20, 4, dark)
			_draw_circle(img, 46, 20, 3, eye)
			_draw_circle(img, 46, 20, 1, Color.WHITE)
			# Hunched body (narrower)
			for y in range(32, 65):
				var width: int = 8 - int(abs(y - 45) * 0.09)
				var hunch: int = int(sin((y - 32) * 0.1) * 4)
				for x in range(36 - width + hunch, 36 + width + hunch):
					if (x + y) % 6 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# One clawed arm
			_draw_arm(img, 44, 36, 70, 0.3, 4, dark)
			for i in range(3):
				_safe_pixel(img, 52 + i * 2, 72 + i, dark)
			# One crouched leg
			_draw_leg(img, 36, 63, 85, 0.15, 5, dark)
		"back":
			# Hunched head (back)
			_draw_circle(img, 36, 22, 11, body)
			_draw_circle(img, 36, 22, 7, dark.lerp(body, 0.5))
			# Hunched body (back)
			for y in range(32, 65):
				var width: int = 14 - int(abs(y - 45) * 0.15)
				var hunch: int = int(sin((y - 32) * 0.1) * 4)
				for x in range(32 - width + hunch, 32 + width + hunch):
					if (x + y) % 6 != 0:
						_safe_pixel(img, x, y, body.darkened(0.1))
					else:
						_safe_pixel(img, x, y, dark)
			# Arms reversed
			_draw_arm(img, 52, 36, 68, -0.4, 4, dark)
			_draw_arm(img, 12, 36, 70, 0.35, 4, dark)
			for i in range(3):
				_safe_pixel(img, 54 - i * 2, 70 + i, dark)
				_safe_pixel(img, 10 + i * 2, 72 + i, dark)
			# Crouched legs
			_draw_leg(img, 24, 63, 85, 0.15, 5, dark)
			_draw_leg(img, 40, 63, 88, -0.15, 5, dark)
		_:  # "front"
			# Hunched head (lower position)
			_draw_circle(img, 36, 22, 11, body)
			# Wide creepy eyes
			_draw_circle(img, 30, 20, 4, dark)
			_draw_circle(img, 42, 20, 4, dark)
			_draw_circle(img, 30, 20, 3, eye)
			_draw_circle(img, 42, 20, 3, eye)
			_draw_circle(img, 30, 20, 1, Color.WHITE)
			_draw_circle(img, 42, 20, 1, Color.WHITE)
			# Hunched body
			for y in range(32, 65):
				var width: int = 14 - int(abs(y - 45) * 0.15)
				var hunch: int = int(sin((y - 32) * 0.1) * 4)
				for x in range(32 - width + hunch, 32 + width + hunch):
					if (x + y) % 6 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Long clawed arms
			_draw_arm(img, 12, 36, 70, 0.4, 4, dark)
			_draw_arm(img, 52, 36, 68, -0.35, 4, dark)
			for i in range(3):
				_safe_pixel(img, 10 + i * 2, 72 + i, dark)
				_safe_pixel(img, 54 - i * 2, 70 + i, dark)
			# Crouched legs
			_draw_leg(img, 24, 63, 85, 0.2, 5, dark)
			_draw_leg(img, 40, 63, 88, -0.15, 5, dark)

	_apply_outline(img, Color(0.1, 0.1, 0.1))
	_apply_lighting(img)
	return ImageTexture.create_from_image(img)


# ==============================================
# TANK
# ==============================================

static func _generate_tank(view_angle: String = "front") -> ImageTexture:
	var img := Image.create(80, 112, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.35, 0.3, 0.32)
	var dark := Color(0.25, 0.2, 0.22)
	var eye := Color(1.0, 0.1, 0.1)
	var scar := Color(0.5, 0.25, 0.25)

	match view_angle:
		"side":
			# Huge head in profile
			_draw_circle(img, 44, 22, 18, body)
			# One tiny eye
			_draw_circle(img, 52, 18, 4, dark)
			_draw_circle(img, 52, 18, 2, eye)
			# Scars (profile)
			for i in range(8):
				_safe_pixel(img, 48 + i, 24 + i % 2, scar)
			# Massive jaw (profile, narrower)
			for x in range(40, 58):
				for y in range(28, 36):
					if (x + y) % 2 == 0:
						_safe_pixel(img, x, y, dark)
			# Enormous body (narrower ~60%)
			for y in range(38, 85):
				var width: int = 17 - int(abs(y - 58) * 0.06)
				for x in range(42 - width, 42 + width):
					if (x + y) % 3 != 0:
						_safe_pixel(img, x, y, body)
					elif (x + y) % 7 == 0:
						_safe_pixel(img, x, y, scar)
					else:
						_safe_pixel(img, x, y, dark)
			# Far-side shading
			_draw_body_shading(img, 42, 38, 85, 17, dark, -1)
			# One massive arm
			for y in range(42, 80):
				var x_base: int = 56 + int((y - 42) * 0.05)
				for dx in range(-8, 8):
					_safe_pixel(img, x_base + dx, y, dark if abs(dx) > 5 else body)
			# One tree trunk leg
			for y in range(83, 110):
				for x in range(34, 50):
					_safe_pixel(img, x, y, dark)
		"back":
			# Huge head (back)
			_draw_circle(img, 40, 22, 18, body)
			_draw_circle(img, 40, 22, 12, dark.lerp(body, 0.5))
			# Scars on back of head
			for i in range(8):
				_safe_pixel(img, 35 + i, 12 + i % 3, scar)
			# Enormous body (back, darker)
			for y in range(38, 85):
				var width: int = 28 - int(abs(y - 58) * 0.1)
				for x in range(40 - width, 40 + width):
					if (x + y) % 3 != 0:
						_safe_pixel(img, x, y, body.darkened(0.1))
					elif (x + y) % 7 == 0:
						_safe_pixel(img, x, y, scar)
					else:
						_safe_pixel(img, x, y, dark)
			# Massive arms (reversed)
			for y in range(42, 80):
				var x_right: int = 71 - int((y - 42) * 0.05)
				var x_left: int = 8 + int((y - 42) * 0.05)
				for dx in range(-8, 8):
					_safe_pixel(img, x_right + dx, y, dark if abs(dx) > 5 else body)
					_safe_pixel(img, x_left + dx, y, dark if abs(dx) > 5 else body)
			# Tree trunk legs
			for y in range(83, 110):
				for x in range(25, 38):
					_safe_pixel(img, x, y, dark)
				for x in range(42, 55):
					_safe_pixel(img, x, y, dark)
		_:  # "front"
			# Huge head
			_draw_circle(img, 40, 22, 18, body)
			# Tiny rage-filled eyes
			_draw_circle(img, 33, 18, 4, dark)
			_draw_circle(img, 47, 18, 4, dark)
			_draw_circle(img, 33, 18, 2, eye)
			_draw_circle(img, 47, 18, 2, eye)
			# Scars
			for i in range(8):
				_safe_pixel(img, 28 + i, 24 + i % 2, scar)
				_safe_pixel(img, 45 + i, 12 + i % 3, scar)
			# Massive jaw
			for x in range(30, 51):
				for y in range(28, 36):
					if (x + y) % 2 == 0:
						_safe_pixel(img, x, y, dark)
			# Enormous body
			for y in range(38, 85):
				var width: int = 28 - int(abs(y - 58) * 0.1)
				for x in range(40 - width, 40 + width):
					if (x + y) % 3 != 0:
						_safe_pixel(img, x, y, body)
					elif (x + y) % 7 == 0:
						_safe_pixel(img, x, y, scar)
					else:
						_safe_pixel(img, x, y, dark)
			# Massive arms
			for y in range(42, 80):
				var x_left: int = 8 + int((y - 42) * 0.05)
				var x_right: int = 71 - int((y - 42) * 0.05)
				for dx in range(-8, 8):
					_safe_pixel(img, x_left + dx, y, dark if abs(dx) > 5 else body)
					_safe_pixel(img, x_right + dx, y, dark if abs(dx) > 5 else body)
			# Tree trunk legs
			for y in range(83, 110):
				for x in range(25, 38):
					_safe_pixel(img, x, y, dark)
				for x in range(42, 55):
					_safe_pixel(img, x, y, dark)

	_apply_outline(img, Color(0.1, 0.1, 0.1))
	_apply_lighting(img)
	return ImageTexture.create_from_image(img)


# ==============================================
# MAGE ZOMBIE
# ==============================================

static func _generate_mage_zombie(view_angle: String = "front") -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.35, 0.3, 0.5)  # Purple robes
	var dark := Color(0.25, 0.2, 0.4)
	var eye := Color(0.3, 1.0, 0.4)
	var magic := Color(0.5, 0.2, 0.8)

	match view_angle:
		"side":
			# Skull-like head (profile)
			_draw_circle(img, 36, 16, 11, Color(0.8, 0.75, 0.7))
			# One glowing eye
			_draw_circle(img, 42, 14, 3, dark)
			_draw_circle(img, 42, 14, 2, eye)
			# Robed body (narrower profile)
			for y in range(26, 75):
				var width: int = 6 + int((y - 26) * 0.12)
				var wave: int = int(sin(y * 0.2) * 2)
				for x in range(34 - width + wave, 34 + width + wave):
					if (x + y) % 5 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Ghostly bottom (profile)
			for y in range(75, 90):
				var alpha: float = 1.0 - (y - 75) / 15.0
				var width: int = 8
				for x in range(34 - width, 34 + width):
					var c := body
					c.a = alpha * 0.7
					_safe_pixel(img, x, y, c)
			# Magic orb visible from side
			_draw_circle(img, 42, 55, 6, magic)
			_draw_circle(img, 42, 55, 3, Color(0.8, 0.5, 1.0))
		"back":
			# Skull-like head (back, no eyes)
			_draw_circle(img, 32, 16, 11, Color(0.8, 0.75, 0.7))
			_draw_circle(img, 32, 16, 7, Color(0.7, 0.65, 0.6))
			# Robed body (back, darker)
			for y in range(26, 75):
				var width: int = 10 + int((y - 26) * 0.2)
				var wave: int = int(sin(y * 0.2) * 2)
				for x in range(32 - width + wave, 32 + width + wave):
					if (x + y) % 5 != 0:
						_safe_pixel(img, x, y, body.darkened(0.1))
					else:
						_safe_pixel(img, x, y, dark)
			# Ghostly bottom
			for y in range(75, 90):
				var alpha: float = 1.0 - (y - 75) / 15.0
				var width: int = 14
				for x in range(32 - width, 32 + width):
					var c := body
					c.a = alpha * 0.7
					_safe_pixel(img, x, y, c)
		_:  # "front"
			# Skull-like head
			_draw_circle(img, 32, 16, 11, Color(0.8, 0.75, 0.7))
			# Glowing eyes
			_draw_circle(img, 27, 14, 3, dark)
			_draw_circle(img, 37, 14, 3, dark)
			_draw_circle(img, 27, 14, 2, eye)
			_draw_circle(img, 37, 14, 2, eye)
			# Robed body
			for y in range(26, 75):
				var width: int = 10 + int((y - 26) * 0.2)
				var wave: int = int(sin(y * 0.2) * 2)
				for x in range(32 - width + wave, 32 + width + wave):
					if (x + y) % 5 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Ghostly bottom
			for y in range(75, 90):
				var alpha: float = 1.0 - (y - 75) / 15.0
				var width: int = 14
				for x in range(32 - width, 32 + width):
					var c := body
					c.a = alpha * 0.7
					_safe_pixel(img, x, y, c)
			# Magic orb
			_draw_circle(img, 32, 55, 6, magic)
			_draw_circle(img, 32, 55, 3, Color(0.8, 0.5, 1.0))

	_apply_outline(img, Color(0.1, 0.1, 0.1))
	_apply_lighting(img)
	return ImageTexture.create_from_image(img)


# ==============================================
# EXPLODER
# ==============================================

static func _generate_exploder(view_angle: String = "front") -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.6, 0.4, 0.3)
	var dark := Color(0.5, 0.3, 0.2)
	var eye := Color(1.0, 0.3, 0.1)
	var pustule := Color(0.7, 0.5, 0.2)

	match view_angle:
		"side":
			# Bloated head (profile)
			_draw_circle(img, 36, 18, 14, body)
			# One angry eye
			_draw_circle(img, 44, 16, 3, dark)
			_draw_circle(img, 44, 16, 2, eye)
			# Bloated body with pustules (narrower profile)
			for y in range(30, 72):
				var bloat: float = sin((y - 30) / 42.0 * PI)
				var width: int = int(7 + bloat * 9)
				for x in range(34 - width, 34 + width):
					var is_pustule: bool = (x * y) % 17 == 0
					if is_pustule:
						_safe_pixel(img, x, y, pustule)
					elif (x + y) % 4 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Far-side shading
			_draw_body_shading(img, 34, 30, 72, 9, dark, -1)
			# One stubby arm
			_draw_arm(img, 42, 38, 55, 0.1, 5, dark)
			# One leg
			_draw_leg(img, 34, 70, 92, 0.03, 6, dark)
			# Warning glow
			for y_g in range(40, 65):
				for x_g in range(26, 43):
					var existing := img.get_pixel(x_g, y_g)
					if existing.a > 0:
						img.set_pixel(x_g, y_g, existing.lerp(Color(1, 0.5, 0.1), 0.15))
		"back":
			# Bloated head (back)
			_draw_circle(img, 32, 18, 14, body)
			_draw_circle(img, 32, 18, 10, dark.lerp(body, 0.5))
			# Bloated body (back, darker)
			for y in range(30, 72):
				var bloat: float = sin((y - 30) / 42.0 * PI)
				var width: int = int(12 + bloat * 14)
				for x in range(32 - width, 32 + width):
					var is_pustule: bool = (x * y) % 17 == 0
					if is_pustule:
						_safe_pixel(img, x, y, pustule)
					elif (x + y) % 4 != 0:
						_safe_pixel(img, x, y, body.darkened(0.1))
					else:
						_safe_pixel(img, x, y, dark)
			# Arms reversed
			_draw_arm(img, 53, 38, 53, -0.15, 5, dark)
			_draw_arm(img, 10, 38, 55, 0.15, 5, dark)
			# Legs
			_draw_leg(img, 24, 70, 92, 0.05, 6, dark)
			_draw_leg(img, 40, 70, 92, -0.05, 6, dark)
			# Warning glow (back)
			for y_g in range(40, 65):
				for x_g in range(24, 41):
					var existing := img.get_pixel(x_g, y_g)
					if existing.a > 0:
						img.set_pixel(x_g, y_g, existing.lerp(Color(1, 0.5, 0.1), 0.1))
		_:  # "front"
			# Bloated head
			_draw_circle(img, 32, 18, 14, body)
			# Angry eyes
			_draw_circle(img, 26, 16, 3, dark)
			_draw_circle(img, 38, 16, 3, dark)
			_draw_circle(img, 26, 16, 2, eye)
			_draw_circle(img, 38, 16, 2, eye)
			# Bloated body with pustules
			for y in range(30, 72):
				var bloat: float = sin((y - 30) / 42.0 * PI)
				var width: int = int(12 + bloat * 14)
				for x in range(32 - width, 32 + width):
					var is_pustule: bool = (x * y) % 17 == 0
					if is_pustule:
						_safe_pixel(img, x, y, pustule)
					elif (x + y) % 4 != 0:
						_safe_pixel(img, x, y, body)
					else:
						_safe_pixel(img, x, y, dark)
			# Short stubby arms
			_draw_arm(img, 10, 38, 55, 0.15, 5, dark)
			_draw_arm(img, 53, 38, 53, -0.15, 5, dark)
			# Short legs
			_draw_leg(img, 24, 70, 92, 0.05, 6, dark)
			_draw_leg(img, 40, 70, 92, -0.05, 6, dark)
			# Warning glow effect
			for y_g in range(40, 65):
				for x_g in range(24, 41):
					var existing := img.get_pixel(x_g, y_g)
					if existing.a > 0:
						img.set_pixel(x_g, y_g, existing.lerp(Color(1, 0.5, 0.1), 0.15))

	_apply_outline(img, Color(0.1, 0.1, 0.1))
	_apply_lighting(img)
	return ImageTexture.create_from_image(img)


# ==============================================
# POST-PROCESSING: Outline and Lighting
# ==============================================

## Draw a 1px dark outline around all non-transparent pixels
static func _apply_outline(img: Image, outline_color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var edge_pixels: Array = []
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1:
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


## Apply left-side lighting for 3D depth effect
static func _apply_lighting(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
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


# ==============================================
# HELPER FUNCTIONS
# ==============================================

static func _draw_circle(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dist := sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
			if dist <= radius:
				_safe_pixel(img, x, y, color)


static func _draw_body(img: Image, cx: int, y_start: int, y_end: int, max_width: int, body: Color, dark: Color) -> void:
	for y in range(y_start, y_end):
		var width: int = max_width - int(abs(y - (y_start + y_end) / 2) * 0.15)
		var x_off: int = randi() % 2
		for x in range(cx - width + x_off, cx + width + x_off):
			if (x + y) % 7 != 0:
				_safe_pixel(img, x, y, body)
			else:
				_safe_pixel(img, x, y, dark)


## Add shading to one side of the body for side-view depth
## direction: -1 for left side (far side), +1 for right side
static func _draw_body_shading(img: Image, cx: int, y_start: int, y_end: int, max_width: int, dark: Color, direction: int) -> void:
	for y in range(y_start, y_end):
		var width: int = max_width - int(abs(y - (y_start + y_end) / 2) * 0.15)
		var shade_width: int = max(1, width / 3)
		var x_start: int
		if direction < 0:
			x_start = cx - width
		else:
			x_start = cx + width - shade_width
		for x in range(x_start, x_start + shade_width):
			var existing := img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
			if existing.a > 0.1:
				_safe_pixel(img, x, y, existing.lerp(dark, 0.4))


static func _draw_arm(img: Image, x_start: int, y_start: int, y_end: int, slope: float, thickness: int, color: Color) -> void:
	for y in range(y_start, y_end):
		var x_base: int = x_start + int((y - y_start) * slope)
		for x in range(x_base - thickness, x_base + thickness):
			_safe_pixel(img, x, y, color)


static func _draw_leg(img: Image, x_start: int, y_start: int, y_end: int, slope: float, thickness: int, color: Color) -> void:
	for y in range(y_start, y_end):
		var x_base: int = x_start + int((y - y_start) * slope)
		for x in range(x_base - thickness, x_base + thickness):
			_safe_pixel(img, x, y, color)


static func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)
