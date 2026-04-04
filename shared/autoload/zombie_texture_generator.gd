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
			# PROFILE VIEW - genuinely different composition, not squished front
			# Head seen from the side (circle, slightly forward from body)
			_draw_circle(img, 38, 16, 11, body)
			# Profile face: one eye, brow ridge, jaw line
			_draw_circle(img, 43, 14, 2, dark)
			_draw_circle(img, 43, 14, 1, eye)
			# Brow ridge (profile)
			for x in range(38, 48):
				_safe_pixel(img, x, 10, dark)
				_safe_pixel(img, x, 11, dark)
			# Protruding jaw (profile, zombie underbite)
			for x in range(40, 50):
				_safe_pixel(img, x, 22, dark)
				_safe_pixel(img, x, 23, body.darkened(0.2))
			# Neck (connecting head to body, visible in profile)
			for y in range(24, 30):
				for dx in range(-3, 4):
					_safe_pixel(img, 34 + dx, y, body.darkened(0.1))
			# Torso - narrow profile (body facing sideways)
			for y in range(28, 65):
				var depth: int = 8 - int(abs(y - 45) * 0.08)
				for dx in range(-depth, depth + 1):
					var shade: float = 0.85 + (float(dx + depth) / float(depth * 2 + 1)) * 0.15
					if (dx + y) % 7 != 0:
						_safe_pixel(img, 34 + dx, y, body * shade)
					else:
						_safe_pixel(img, 34 + dx, y, dark)
			# One arm reaching forward (zombie shamble pose)
			# Upper arm from shoulder forward
			for y in range(32, 44):
				var x_base: int = 38 + int((y - 32) * 0.6)  # Reaching forward
				for dx in range(-3, 4):
					_safe_pixel(img, x_base + dx, y, dark)
			# Forearm/hand stretched out
			for y in range(42, 56):
				var x_base: int = 45 + int((y - 42) * 0.15)
				for dx in range(-2, 3):
					_safe_pixel(img, x_base + dx, y, dark)
			# Dangling fingers
			for i in range(3):
				_safe_pixel(img, 46 + i, 56, dark)
				_safe_pixel(img, 46 + i, 57, dark)
			# Front leg (stepping forward)
			for y in range(64, 90):
				var x_base: int = 38 + int((y - 64) * 0.15)
				for dx in range(-4, 5):
					_safe_pixel(img, x_base + dx, y, dark)
			# Back leg (trailing behind)
			for y in range(64, 88):
				var x_base: int = 30 - int((y - 64) * 0.08)
				for dx in range(-4, 5):
					_safe_pixel(img, x_base + dx, y, dark.lerp(body, 0.3))
			# Foot on front leg
			for dx in range(-5, 6):
				_safe_pixel(img, 42 + dx, 90, dark)
				_safe_pixel(img, 42 + dx, 91, dark)
		"back":
			# BACK VIEW - genuinely different composition
			# Head from behind (round, no face features)
			_draw_circle(img, 32, 16, 12, body)
			# Back of skull - darker center with some texture
			_draw_circle(img, 32, 15, 7, body.darkened(0.15))
			# Patchy hair/scalp detail on back of head
			for i in range(6):
				var hx: int = 28 + (i * 3) % 10
				var hy: int = 10 + (i * 2) % 6
				_safe_pixel(img, hx, hy, dark)
				_safe_pixel(img, hx + 1, hy, dark)
			# Ears visible from back (bumps on sides of head)
			_draw_circle(img, 20, 16, 3, body.darkened(0.1))
			_draw_circle(img, 44, 16, 3, body.darkened(0.1))
			# Neck
			for y in range(25, 30):
				for dx in range(-4, 5):
					_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
			# Shoulders and upper back (broader than front)
			for y in range(28, 38):
				var width: int = 18 - int(abs(y - 33) * 0.4)
				for dx in range(-width, width + 1):
					_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
			# Back torso
			for y in range(36, 68):
				var width: int = 16 - int(abs(y - 50) * 0.15)
				for dx in range(-width, width + 1):
					# Spine detail down the center
					if abs(dx) <= 1 and y % 4 == 0:
						_safe_pixel(img, 32 + dx, y, dark)
					elif (dx + y) % 7 != 0:
						_safe_pixel(img, 32 + dx, y, body.darkened(0.12))
					else:
						_safe_pixel(img, 32 + dx, y, dark)
			# Arms hanging at sides, slightly forward (reaching pose from behind)
			# Left arm
			_draw_arm(img, 14, 32, 58, 0.2, 4, dark)
			# Right arm
			_draw_arm(img, 49, 32, 56, -0.15, 4, dark)
			# Legs from behind (slightly apart)
			_draw_leg(img, 25, 68, 92, -0.03, 5, dark)
			_draw_leg(img, 39, 68, 94, 0.03, 5, dark)
			# Feet
			for dx in range(-5, 6):
				_safe_pixel(img, 24 + dx, 92, dark)
				_safe_pixel(img, 40 + dx, 94, dark)
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
			# PROFILE VIEW - runner in aggressive sprint pose
			# Head leaning forward (profile)
			_draw_circle(img, 42, 14, 9, body)
			# One angry eye
			_draw_circle(img, 47, 12, 2, dark)
			_draw_circle(img, 47, 12, 1, eye)
			# Snarling mouth with teeth (profile, jaw open)
			for x in range(44, 52):
				_safe_pixel(img, x, 18, dark)
				_safe_pixel(img, x, 19, dark)
				if x % 2 == 0:
					_safe_pixel(img, x, 20, Color.WHITE)  # Teeth
			# Leaning neck (forward lean for sprinting)
			for y in range(20, 28):
				var x_base: int = 40 - int((y - 20) * 0.4)
				for dx in range(-2, 3):
					_safe_pixel(img, x_base + dx, y, body.darkened(0.1))
			# Thin torso (profile, leaning forward)
			for y in range(26, 62):
				var lean: int = int((62 - y) * 0.12)  # Lean forward at top
				var depth: int = 6 - int(abs(y - 42) * 0.06)
				for dx in range(-depth, depth + 1):
					if (dx + y) % 5 != 0:
						_safe_pixel(img, 34 + dx + lean, y, body)
					else:
						_safe_pixel(img, 34 + dx + lean, y, dark)
			# Front arm - reaching far forward (sprinting)
			for y in range(30, 48):
				var x_base: int = 40 + int((y - 30) * 0.5)
				for dx in range(-2, 3):
					_safe_pixel(img, x_base + dx, y, dark)
			# Clawed hand
			for i in range(3):
				_safe_pixel(img, 50 + i, 48 + i, dark)
			# Back arm - trailing behind
			for y in range(32, 50):
				var x_base: int = 28 - int((y - 32) * 0.2)
				for dx in range(-2, 3):
					_safe_pixel(img, x_base + dx, y, dark.lerp(body, 0.3))
			# Front leg - extended forward in sprint stride
			for y in range(60, 88):
				var x_base: int = 40 + int((y - 60) * 0.2)
				for dx in range(-3, 4):
					_safe_pixel(img, x_base + dx, y, dark)
			# Back leg - pushing off behind
			for y in range(60, 84):
				var x_base: int = 28 - int((y - 60) * 0.15)
				for dx in range(-3, 4):
					_safe_pixel(img, x_base + dx, y, dark.lerp(body, 0.3))
		"back":
			# BACK VIEW - runner seen from behind, leaning forward
			# Head (no face, leaning forward so slightly higher)
			_draw_circle(img, 32, 12, 9, body)
			_draw_circle(img, 32, 11, 5, dark.lerp(body, 0.5))
			# Neck (visible because head is forward-leaning)
			for y in range(18, 26):
				for dx in range(-3, 4):
					_safe_pixel(img, 32 + dx, y, body.darkened(0.15))
			# Shoulder blades visible (lean runner)
			for y in range(24, 34):
				var width: int = 14 - int(abs(y - 29) * 0.5)
				for dx in range(-width, width + 1):
					_safe_pixel(img, 32 + dx, y, body.darkened(0.08))
			# Visible shoulder blade bumps
			_draw_circle(img, 24, 30, 3, body.darkened(0.2))
			_draw_circle(img, 40, 30, 3, body.darkened(0.2))
			# Thin torso from back
			for y in range(32, 62):
				var width: int = 10 - int(abs(y - 44) * 0.1)
				for dx in range(-width, width + 1):
					# Spine ridge
					if abs(dx) <= 1 and y % 3 == 0:
						_safe_pixel(img, 32 + dx, y, dark)
					elif (dx + y) % 5 != 0:
						_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
					else:
						_safe_pixel(img, 32 + dx, y, dark)
			# Arms pumping (from behind)
			_draw_arm(img, 46, 28, 56, -0.25, 3, dark)
			_draw_arm(img, 18, 28, 58, 0.2, 3, dark)
			# Legs in sprint stride
			_draw_leg(img, 26, 60, 88, 0.12, 4, dark)
			_draw_leg(img, 38, 60, 86, -0.1, 4, dark)
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
			# PROFILE VIEW - massive brute seen from the side
			# Big head in profile (slightly forward, hunched)
			_draw_circle(img, 38, 18, 13, body)
			# One small eye under heavy brow
			_draw_circle(img, 44, 16, 2, dark)
			_draw_circle(img, 44, 16, 1, eye)
			# Heavy brow ridge protruding forward (profile)
			for x in range(38, 52):
				for y_b in range(11, 14):
					_safe_pixel(img, x, y_b, dark)
			# Massive jaw (profile)
			for x in range(36, 48):
				for y_j in range(24, 30):
					_safe_pixel(img, x, y_j, body.darkened(0.15))
			# Thick neck (brute has a bull neck)
			for y in range(28, 34):
				for dx in range(-6, 7):
					_safe_pixel(img, 34 + dx, y, body.darkened(0.1))
			# Huge barrel torso (profile - deep chest)
			for y in range(32, 70):
				var depth: int = 14 - int(abs(y - 50) * 0.1)
				for dx in range(-depth, depth + 1):
					var shade: float = 0.8 + (float(dx + depth) / float(depth * 2 + 1)) * 0.2
					if (dx + y) % 4 != 0:
						_safe_pixel(img, 34 + dx, y, body * shade)
					else:
						_safe_pixel(img, 34 + dx, y, dark)
			# One massive arm hanging down (close side)
			for y in range(36, 68):
				var x_base: int = 48 + int((y - 36) * 0.03)
				for dx in range(-6, 7):
					_safe_pixel(img, x_base + dx, y, dark if abs(dx) > 4 else body.darkened(0.05))
			# Huge fist
			_draw_circle(img, 50, 68, 5, dark)
			# One thick leg
			for y in range(68, 95):
				for dx in range(-6, 7):
					_safe_pixel(img, 34 + dx, y, dark)
			# Big flat foot
			for dx in range(-7, 8):
				_safe_pixel(img, 34 + dx, 93, dark)
				_safe_pixel(img, 34 + dx, 94, dark)
		"back":
			# BACK VIEW - massive wide back
			# Big head from behind (no face)
			_draw_circle(img, 32, 18, 14, body)
			_draw_circle(img, 32, 17, 8, body.darkened(0.15))
			# Thick neck connecting to trapezius muscles
			for y in range(28, 36):
				var width: int = 8 + int((y - 28) * 1.2)
				for dx in range(-width, width + 1):
					_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
			# Massive back with muscle definition
			for y in range(34, 70):
				var width: int = 22 - int(abs(y - 50) * 0.12)
				for dx in range(-width, width + 1):
					# Spine groove
					if abs(dx) <= 1:
						_safe_pixel(img, 32 + dx, y, dark)
					# Shoulder blade bumps
					elif y >= 36 and y <= 48 and (abs(dx) >= 8 and abs(dx) <= 12):
						_safe_pixel(img, 32 + dx, y, body.darkened(0.2))
					elif (dx + y) % 4 != 0:
						_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
					else:
						_safe_pixel(img, 32 + dx, y, dark)
			# Massive arms at sides
			for y in range(36, 66):
				# Left arm
				var xl: int = 8 + int((y - 36) * 0.05)
				for dx in range(-6, 7):
					_safe_pixel(img, xl + dx, y, dark if abs(dx) > 4 else body)
				# Right arm
				var xr: int = 55 - int((y - 36) * 0.05)
				for dx in range(-6, 7):
					_safe_pixel(img, xr + dx, y, dark if abs(dx) > 4 else body)
			# Fists
			_draw_circle(img, 10, 66, 5, dark)
			_draw_circle(img, 53, 66, 5, dark)
			# Thick legs
			_draw_leg(img, 23, 70, 95, 0.02, 7, dark)
			_draw_leg(img, 41, 70, 95, -0.02, 7, dark)
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
			# PROFILE VIEW - crouching leaper in coiled-to-pounce pose
			# Head low and forward (hunched profile)
			_draw_circle(img, 44, 24, 10, body)
			# One large creepy eye (profile)
			_draw_circle(img, 50, 22, 3, dark)
			_draw_circle(img, 50, 22, 2, eye)
			_draw_circle(img, 50, 22, 1, Color.WHITE)
			# Open mouth with teeth
			for x in range(48, 54):
				_safe_pixel(img, x, 28, dark)
				_safe_pixel(img, x, 29, dark)
			# Hunched spine (curved back, visible in profile)
			for y in range(28, 58):
				# Curved spine - body arcs forward
				var curve: float = sin((y - 28) / 30.0 * PI) * 8
				var depth: int = 7 - int(abs(y - 42) * 0.1)
				var cx_body: int = int(36 + curve)
				for dx in range(-depth, depth + 1):
					if (dx + y) % 6 != 0:
						_safe_pixel(img, cx_body + dx, y, body)
					else:
						_safe_pixel(img, cx_body + dx, y, dark)
			# Protruding spine bumps (visible on hunched back)
			for y in range(30, 50):
				var curve_x: int = int(36 + sin((y - 28) / 30.0 * PI) * 8)
				_safe_pixel(img, curve_x - 7, y, dark)
				if y % 3 == 0:
					_safe_pixel(img, curve_x - 8, y, dark)
			# Long clawed arm reaching forward and down
			for y in range(34, 60):
				var x_base: int = 46 + int((y - 34) * 0.3)
				for dx in range(-3, 4):
					_safe_pixel(img, x_base + dx, y, dark)
			# Claws on hand
			for i in range(3):
				_safe_pixel(img, 54 + i * 2, 60 + i, dark)
				_safe_pixel(img, 54 + i * 2, 61 + i, dark)
			# Crouched legs (coiled, ready to spring)
			# Thigh (angled forward)
			for y in range(55, 68):
				var x_base: int = 38 + int((y - 55) * 0.4)
				for dx in range(-4, 5):
					_safe_pixel(img, x_base + dx, y, dark)
			# Shin (angled back, crouched)
			for y in range(66, 82):
				var x_base: int = 44 - int((y - 66) * 0.15)
				for dx in range(-3, 4):
					_safe_pixel(img, x_base + dx, y, dark)
			# Foot with claws
			for dx in range(-4, 5):
				_safe_pixel(img, 42 + dx, 82, dark)
			for i in range(3):
				_safe_pixel(img, 44 + i * 2, 83 + i, dark)
		"back":
			# BACK VIEW - hunched leaper showing curved spine
			# Head low (hunched forward, so seen from above/behind)
			_draw_circle(img, 32, 26, 10, body)
			_draw_circle(img, 32, 25, 6, body.darkened(0.15))
			# Prominent hunched back/spine
			for y in range(30, 60):
				var width: int = 13 - int(abs(y - 44) * 0.15)
				for dx in range(-width, width + 1):
					# Prominent spine ridge
					if abs(dx) <= 1:
						_safe_pixel(img, 32 + dx, y, dark.darkened(0.2))
					# Protruding vertebrae bumps
					elif abs(dx) <= 3 and y % 4 == 0:
						_safe_pixel(img, 32 + dx, y, dark)
					# Ribs visible on thin body
					elif abs(dx) >= 6 and y % 3 == 0 and y < 50:
						_safe_pixel(img, 32 + dx, y, dark)
					elif (dx + y) % 6 != 0:
						_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
					else:
						_safe_pixel(img, 32 + dx, y, dark)
			# Long arms reaching forward (from behind, they go toward viewer)
			# Left arm
			_draw_arm(img, 16, 34, 62, 0.3, 4, dark)
			# Right arm
			_draw_arm(img, 48, 34, 60, -0.25, 4, dark)
			# Claws
			for i in range(3):
				_safe_pixel(img, 14 + i * 2, 64 + i, dark)
				_safe_pixel(img, 50 - i * 2, 62 + i, dark)
			# Crouched legs
			_draw_leg(img, 24, 58, 82, 0.1, 5, dark)
			_draw_leg(img, 40, 58, 84, -0.1, 5, dark)
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
			# PROFILE VIEW - enormous tank seen from the side
			# Huge head in profile (forward-jutting)
			_draw_circle(img, 46, 22, 16, body)
			# One tiny rage-filled eye under massive brow
			_draw_circle(img, 54, 18, 3, dark)
			_draw_circle(img, 54, 18, 1, eye)
			# Massive brow ridge (profile, overhanging)
			for x in range(44, 62):
				for y_b in range(12, 16):
					_safe_pixel(img, x, y_b, dark)
			# Scars across cheek
			for i in range(6):
				_safe_pixel(img, 50 + i, 24 + i % 2, scar)
			# Enormous jaw (profile, underbite)
			for x in range(44, 60):
				for y_j in range(30, 38):
					if (x + y_j) % 2 == 0:
						_safe_pixel(img, x, y_j, dark)
			# Bull neck
			for y in range(34, 42):
				for dx in range(-8, 9):
					_safe_pixel(img, 40 + dx, y, body.darkened(0.1))
			# Massive barrel chest and gut (profile - very deep)
			for y in range(40, 84):
				var depth: int = 18 - int(abs(y - 60) * 0.08)
				for dx in range(-depth, depth + 1):
					var shade: float = 0.75 + (float(dx + depth) / float(depth * 2 + 1)) * 0.25
					if (dx + y) % 7 == 0:
						_safe_pixel(img, 40 + dx, y, scar)
					elif (dx + y) % 3 != 0:
						_safe_pixel(img, 40 + dx, y, body * shade)
					else:
						_safe_pixel(img, 40 + dx, y, dark)
			# One massive arm hanging at side
			for y in range(44, 78):
				var x_base: int = 58 + int((y - 44) * 0.03)
				for dx in range(-7, 8):
					_safe_pixel(img, x_base + dx, y, dark if abs(dx) > 5 else body)
			# Enormous fist
			_draw_circle(img, 60, 78, 6, dark)
			# One tree trunk leg
			for y in range(82, 110):
				for dx in range(-8, 9):
					_safe_pixel(img, 40 + dx, y, dark)
			# Foot
			for dx in range(-10, 11):
				_safe_pixel(img, 40 + dx, 108, dark)
				_safe_pixel(img, 40 + dx, 109, dark)
		"back":
			# BACK VIEW - mountain of muscle from behind
			# Huge head from behind
			_draw_circle(img, 40, 22, 16, body)
			_draw_circle(img, 40, 20, 10, body.darkened(0.15))
			# Scars on back of skull
			for i in range(8):
				_safe_pixel(img, 34 + i, 12 + i % 3, scar)
				_safe_pixel(img, 36 + i, 14 + i % 2, scar)
			# Massive trapezius/neck (mountain of muscle connecting head to shoulders)
			for y in range(32, 44):
				var width: int = 10 + int((y - 32) * 1.5)
				for dx in range(-width, width + 1):
					_safe_pixel(img, 40 + dx, y, body.darkened(0.1))
			# Enormous wide back
			for y in range(42, 84):
				var width: int = 28 - int(abs(y - 60) * 0.1)
				for dx in range(-width, width + 1):
					# Deep spine groove
					if abs(dx) <= 2:
						_safe_pixel(img, 40 + dx, y, dark.darkened(0.1))
					# Massive lat muscles (bulge on sides)
					elif abs(dx) >= width - 4:
						_safe_pixel(img, 40 + dx, y, body.darkened(0.2))
					elif (dx + y) % 7 == 0:
						_safe_pixel(img, 40 + dx, y, scar)
					elif (dx + y) % 3 != 0:
						_safe_pixel(img, 40 + dx, y, body.darkened(0.1))
					else:
						_safe_pixel(img, 40 + dx, y, dark)
			# Massive arms at sides
			for y in range(44, 78):
				var xl: int = 8 + int((y - 44) * 0.03)
				var xr: int = 71 - int((y - 44) * 0.03)
				for dx in range(-7, 8):
					_safe_pixel(img, xl + dx, y, dark if abs(dx) > 5 else body)
					_safe_pixel(img, xr + dx, y, dark if abs(dx) > 5 else body)
			# Fists
			_draw_circle(img, 10, 78, 6, dark)
			_draw_circle(img, 69, 78, 6, dark)
			# Tree trunk legs
			for y in range(82, 110):
				for x in range(26, 40):
					_safe_pixel(img, x, y, dark)
				for x in range(44, 58):
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
			# PROFILE VIEW - floating mage zombie in profile
			# Skull in profile (elongated, not just narrowed circle)
			_draw_circle(img, 38, 16, 10, Color(0.8, 0.75, 0.7))
			# Elongated skull back
			for y in range(10, 24):
				for dx in range(-4, 1):
					var dist: float = abs(y - 16) * 0.5
					if dist < 4:
						_safe_pixel(img, 30 + dx, y, Color(0.75, 0.70, 0.65))
			# One glowing eye socket (deep, hollow)
			_draw_circle(img, 43, 14, 3, Color(0.2, 0.15, 0.1))
			_draw_circle(img, 43, 14, 2, eye)
			# Jaw/teeth visible in profile
			for x in range(40, 48):
				_safe_pixel(img, x, 20, dark)
				if x % 2 == 0:
					_safe_pixel(img, x, 21, Color(0.9, 0.85, 0.8))
			# Hood/cowl of robe (draped, profile)
			for y in range(10, 24):
				var hood_w: int = 12 - int(abs(y - 14) * 0.6)
				for dx in range(-hood_w, hood_w + 1):
					var existing := img.get_pixel(clampi(36 + dx, 0, 63), clampi(y, 0, 95))
					if existing.a < 0.1:
						_safe_pixel(img, 36 + dx, y, dark)
			# Robed body (profile - flowing robe silhouette)
			for y in range(24, 72):
				var robe_width: int = 6 + int((y - 24) * 0.15)
				var wave: int = int(sin(y * 0.15) * 2)
				for dx in range(-robe_width, robe_width + 1):
					# Robe folds visible in profile
					if abs(dx) == robe_width or abs(dx) == robe_width - 1:
						_safe_pixel(img, 34 + dx + wave, y, dark)
					elif (dx + y) % 5 != 0:
						_safe_pixel(img, 34 + dx + wave, y, body)
					else:
						_safe_pixel(img, 34 + dx + wave, y, dark)
			# Ghostly bottom (wisps trailing)
			for y in range(72, 90):
				var alpha: float = 1.0 - (y - 72) / 18.0
				var wisp_w: int = int(8 * alpha)
				var wave: int = int(sin(y * 0.3) * 3)
				for dx in range(-wisp_w, wisp_w + 1):
					var c := body
					c.a = alpha * 0.6
					_safe_pixel(img, 34 + dx + wave, y, c)
			# One arm extended holding magic orb
			for y in range(36, 54):
				var x_base: int = 42 + int((y - 36) * 0.2)
				for dx in range(-2, 3):
					_safe_pixel(img, x_base + dx, y, dark)
			# Magic orb floating at extended hand
			_draw_circle(img, 46, 54, 5, magic)
			_draw_circle(img, 46, 54, 2, Color(0.8, 0.5, 1.0))
		"back":
			# BACK VIEW - hooded mage from behind
			# Hood of robe (prominent from behind)
			for y in range(6, 26):
				var hood_w: int = 12 - int(abs(y - 14) * 0.5)
				for dx in range(-hood_w, hood_w + 1):
					if abs(dx) >= hood_w - 1:
						_safe_pixel(img, 32 + dx, y, dark.darkened(0.2))
					else:
						_safe_pixel(img, 32 + dx, y, dark)
			# Back of skull visible inside hood
			_draw_circle(img, 32, 16, 8, Color(0.7, 0.65, 0.6))
			# Robed back (wider than front, showing robe drape)
			for y in range(24, 72):
				var robe_width: int = 10 + int((y - 24) * 0.2)
				var wave: int = int(sin(y * 0.15) * 2)
				for dx in range(-robe_width, robe_width + 1):
					# Robe seam down center back
					if abs(dx) <= 1 and y % 3 == 0:
						_safe_pixel(img, 32 + dx + wave, y, dark.darkened(0.15))
					# Robe edges/folds
					elif abs(dx) >= robe_width - 2:
						_safe_pixel(img, 32 + dx + wave, y, dark)
					elif (dx + y) % 5 != 0:
						_safe_pixel(img, 32 + dx + wave, y, body.darkened(0.1))
					else:
						_safe_pixel(img, 32 + dx + wave, y, dark)
			# Ghostly bottom (wisps)
			for y in range(72, 90):
				var alpha: float = 1.0 - (y - 72) / 18.0
				var wisp_w: int = int(14 * alpha)
				for dx in range(-wisp_w, wisp_w + 1):
					var c := body
					c.a = alpha * 0.6
					_safe_pixel(img, 32 + dx, y, c)
			# Faint magic glow from in front (visible aura around hands)
			for y in range(48, 58):
				for dx in range(-3, 4):
					var c := magic
					c.a = 0.3
					_safe_pixel(img, 18 + dx, y, c)
					_safe_pixel(img, 46 + dx, y, c)
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
			# PROFILE VIEW - bloated exploder in profile showing distended belly
			# Head in profile (slightly smaller than body)
			_draw_circle(img, 38, 18, 12, body)
			# One pained eye
			_draw_circle(img, 44, 16, 2, dark)
			_draw_circle(img, 44, 16, 1, eye)
			# Open mouth (in pain/about to explode)
			for x in range(44, 50):
				_safe_pixel(img, x, 22, dark)
				_safe_pixel(img, x, 23, dark)
			# Short neck
			for y in range(26, 32):
				for dx in range(-4, 5):
					_safe_pixel(img, 34 + dx, y, body.darkened(0.1))
			# MASSIVE bloated belly (profile - the key feature, like a balloon)
			# The belly protrudes forward significantly in profile
			for y in range(30, 72):
				var bloat: float = sin((y - 30) / 42.0 * PI)
				# Profile belly: deeper toward the front, flat-ish on back
				var front_depth: int = int(4 + bloat * 14)  # Belly sticks out forward
				var back_depth: int = int(4 + bloat * 6)    # Back is flatter
				for dx in range(-back_depth, front_depth + 1):
					var is_pustule: bool = false
					# Pustules more on the stretched belly surface
					if dx > 0 and bloat > 0.3:
						is_pustule = (dx * y) % 11 == 0
					if is_pustule:
						_safe_pixel(img, 34 + dx, y, pustule)
					elif (dx + y) % 4 != 0:
						_safe_pixel(img, 34 + dx, y, body)
					else:
						_safe_pixel(img, 34 + dx, y, dark)
			# Veins/stretch marks on belly (profile, visible on stretched skin)
			for y in range(40, 65):
				var vein_x: int = 34 + int(sin(y * 0.3) * 3) + 6
				_safe_pixel(img, vein_x, y, dark.lerp(Color(0.6, 0.2, 0.2), 0.5))
			# One stubby arm (pushed aside by belly)
			for y in range(34, 50):
				var x_base: int = 46 + int((y - 34) * 0.15)
				for dx in range(-3, 4):
					_safe_pixel(img, x_base + dx, y, dark)
			# Short stubby legs (struggling under weight)
			for y in range(70, 92):
				for dx in range(-5, 6):
					_safe_pixel(img, 34 + dx, y, dark)
			# Warning glow from belly
			for y_g in range(38, 65):
				for x_g in range(30, 50):
					var existing := img.get_pixel(x_g, y_g)
					if existing.a > 0:
						img.set_pixel(x_g, y_g, existing.lerp(Color(1, 0.5, 0.1), 0.15))
		"back":
			# BACK VIEW - bloated exploder from behind (round silhouette)
			# Head from behind (small compared to body)
			_draw_circle(img, 32, 18, 12, body)
			_draw_circle(img, 32, 17, 7, body.darkened(0.15))
			# Short neck (barely visible, shoulders are up)
			for y in range(26, 32):
				for dx in range(-4, 5):
					_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
			# Bloated body from behind (round, wider than tall)
			for y in range(30, 72):
				var bloat: float = sin((y - 30) / 42.0 * PI)
				var width: int = int(10 + bloat * 16)
				for dx in range(-width, width + 1):
					# Pustules on back
					var is_pustule: bool = (dx * y) % 13 == 0 and bloat > 0.2
					if is_pustule:
						_safe_pixel(img, 32 + dx, y, pustule)
					# Spine stretched tight over bloated back
					elif abs(dx) <= 1 and y % 4 == 0:
						_safe_pixel(img, 32 + dx, y, dark)
					elif (dx + y) % 4 != 0:
						_safe_pixel(img, 32 + dx, y, body.darkened(0.1))
					else:
						_safe_pixel(img, 32 + dx, y, dark)
			# Stretch marks on back
			for y in range(38, 62):
				var mark_x1: int = 32 + int(sin(y * 0.2) * 5) + 8
				var mark_x2: int = 32 - int(sin(y * 0.25) * 4) - 7
				_safe_pixel(img, mark_x1, y, dark.lerp(Color(0.6, 0.2, 0.2), 0.4))
				_safe_pixel(img, mark_x2, y, dark.lerp(Color(0.6, 0.2, 0.2), 0.4))
			# Stubby arms pushed out by belly
			_draw_arm(img, 52, 36, 52, -0.2, 4, dark)
			_draw_arm(img, 12, 36, 54, 0.2, 4, dark)
			# Short legs (bowed under weight)
			_draw_leg(img, 24, 70, 92, -0.05, 6, dark)
			_draw_leg(img, 40, 70, 92, 0.05, 6, dark)
			# Warning glow (visible from behind too)
			for y_g in range(40, 65):
				for x_g in range(20, 45):
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
