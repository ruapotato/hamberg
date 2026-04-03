extends Node
## Generates procedural pixel art textures for different zombie types
## Copied from Zombies-vs-Humans for consistent art style

# Cached textures so we don't regenerate every spawn
static var texture_cache: Dictionary = {}

static func get_zombie_texture(zombie_type: String) -> ImageTexture:
	if zombie_type in texture_cache:
		return texture_cache[zombie_type]

	var tex := _generate_texture(zombie_type)
	texture_cache[zombie_type] = tex
	return tex


static func _generate_texture(zombie_type: String) -> ImageTexture:
	match zombie_type:
		"runner":
			return _generate_runner()
		"brute":
			return _generate_brute()
		"leaper":
			return _generate_leaper()
		"tank":
			return _generate_tank()
		"mage", "mage_zombie":
			return _generate_mage_zombie()
		"exploder":
			return _generate_exploder()
		_:
			return _generate_walker()


static func _generate_walker() -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.4, 0.55, 0.35)
	var dark := Color(0.3, 0.42, 0.28)
	var eye := Color(0.9, 0.2, 0.2)

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
	_draw_arm(img, 14, 32, 60, 0.2, 4, dark)  # Left
	_draw_arm(img, 49, 32, 58, -0.15, 4, dark)  # Right

	# Legs
	_draw_leg(img, 24, 68, 94, 0.1, 5, dark)  # Left
	_draw_leg(img, 40, 68, 92, -0.05, 5, dark)  # Right

	return ImageTexture.create_from_image(img)


static func _generate_runner() -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.55, 0.35, 0.35)
	var dark := Color(0.42, 0.28, 0.28)
	var eye := Color(1.0, 0.3, 0.1)

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
			_safe_pixel(img, x, 21, Color.WHITE)  # Teeth

	# Thin body (leaning forward)
	for y in range(24, 68):
		var width: int = 12 - int(abs(y - 42) * 0.1)
		var lean: int = int((y - 24) * 0.1)
		for x in range(32 - width + lean, 32 + width + lean):
			if (x + y) % 5 != 0:
				_safe_pixel(img, x, y, body)
			else:
				_safe_pixel(img, x, y, dark)

	# Long arms (reaching forward)
	_draw_arm(img, 18, 28, 62, 0.3, 3, dark)
	_draw_arm(img, 46, 28, 60, -0.25, 3, dark)

	# Athletic legs
	_draw_leg(img, 26, 66, 92, 0.15, 4, dark)
	_draw_leg(img, 38, 66, 94, -0.1, 4, dark)

	return ImageTexture.create_from_image(img)


static func _generate_brute() -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.45, 0.4, 0.35)
	var dark := Color(0.32, 0.28, 0.25)
	var eye := Color(0.8, 0.5, 0.1)

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

	return ImageTexture.create_from_image(img)


static func _generate_leaper() -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.5, 0.35, 0.4)
	var dark := Color(0.38, 0.25, 0.3)
	var eye := Color(0.2, 1.0, 0.3)  # Green glowing eyes

	# Hunched head (lower position)
	_draw_circle(img, 36, 22, 11, body)
	# Wide creepy eyes
	_draw_circle(img, 30, 20, 4, dark)
	_draw_circle(img, 42, 20, 4, dark)
	_draw_circle(img, 30, 20, 3, eye)
	_draw_circle(img, 42, 20, 3, eye)
	_draw_circle(img, 30, 20, 1, Color.WHITE)  # Glint
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
	# Claws
	for i in range(3):
		_safe_pixel(img, 10 + i * 2, 72 + i, dark)
		_safe_pixel(img, 54 - i * 2, 70 + i, dark)

	# Crouched legs
	_draw_leg(img, 24, 63, 85, 0.2, 5, dark)
	_draw_leg(img, 40, 63, 88, -0.15, 5, dark)

	return ImageTexture.create_from_image(img)


static func _generate_tank() -> ImageTexture:
	var img := Image.create(80, 112, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.35, 0.3, 0.32)
	var dark := Color(0.25, 0.2, 0.22)
	var eye := Color(1.0, 0.1, 0.1)
	var scar := Color(0.5, 0.25, 0.25)

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

	return ImageTexture.create_from_image(img)


static func _generate_mage_zombie() -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.35, 0.3, 0.5)  # Purple robes
	var dark := Color(0.25, 0.2, 0.4)
	var eye := Color(0.3, 1.0, 0.4)  # Green glowing eyes
	var magic := Color(0.5, 0.2, 0.8)

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

	return ImageTexture.create_from_image(img)


static func _generate_exploder() -> ImageTexture:
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body := Color(0.6, 0.4, 0.3)
	var dark := Color(0.5, 0.3, 0.2)
	var eye := Color(1.0, 0.3, 0.1)
	var pustule := Color(0.7, 0.5, 0.2)

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
	for y in range(40, 65):
		for x in range(24, 41):
			var existing := img.get_pixel(x, y)
			if existing.a > 0:
				img.set_pixel(x, y, existing.lerp(Color(1, 0.5, 0.1), 0.15))

	return ImageTexture.create_from_image(img)


# Helper functions
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
