extends Node3D
class_name FirstPersonArms

## First-person arms and wand visible from player's perspective
## Uses 2D billboard sprites for Paper Mario style

# Billboard sprites
var arm_sprite: Sprite3D
var wand_sprite: Sprite3D

# Animation state
var idle_time: float = 0.0
var cast_animation_time: float = 0.0
var is_casting: bool = false

# Spell color for wand glow
var current_spell_color: Color = Color(1, 0.5, 0.2)

# Colors
var skin_color: Color = Color(0.96, 0.80, 0.69)
var robe_color: Color = Color(0.2, 0.3, 0.7)


func _ready() -> void:
	_create_arm_sprite()
	_create_wand_sprite()


func _process(delta: float) -> void:
	idle_time += delta

	if not is_casting:
		_animate_idle(delta)
	else:
		_animate_cast(delta)


func _create_arm_sprite() -> void:
	arm_sprite = Sprite3D.new()
	arm_sprite.name = "ArmSprite"

	# Generate arm texture (32x48 - robe sleeve + skin + hand)
	var img = Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	_draw_arm_texture(img)

	arm_sprite.texture = ImageTexture.create_from_image(img)
	arm_sprite.pixel_size = 0.01
	arm_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	arm_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # Fixed relative to camera
	arm_sprite.position = Vector3(0.15, -0.2, -0.35)

	add_child(arm_sprite)


func _draw_arm_texture(img: Image) -> void:
	var cx: int = 16
	#var by: int = 44

	# Robe sleeve
	for y in range(0, 20):
		var width: int = 6 - y / 5
		for dx in range(-width, width + 1):
			var px: int = cx + dx
			if px >= 0 and px < 32:
				var shade: float = 0.85 + randf() * 0.15
				img.set_pixel(px, y, robe_color * shade)

	# Arm/skin
	for y in range(18, 35):
		var width: int = 4 - (y - 18) / 8
		for dx in range(-width, width + 1):
			var px: int = cx + dx
			if px >= 0 and px < 32:
				var shade: float = 0.9 + randf() * 0.1
				img.set_pixel(px, y, skin_color * shade)

	# Hand (gripping)
	for dy in range(-3, 4):
		for dx in range(-4, 5):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 4:
				var px: int = cx + dx
				var py: int = 38 + dy
				if px >= 0 and px < 32 and py >= 0 and py < 48:
					img.set_pixel(px, py, skin_color * 0.95)

	# Fingers curled
	for i in range(3):
		var px: int = cx - 2 + i * 2
		for py in range(40, 45):
			if px >= 0 and px < 32:
				img.set_pixel(px, py, skin_color * 0.9)


func _create_wand_sprite() -> void:
	wand_sprite = Sprite3D.new()
	wand_sprite.name = "WandSprite"

	# Generate wand texture (16x48 - wood shaft + colored crystal tip)
	var img = Image.create(16, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	_draw_wand_texture(img)

	wand_sprite.texture = ImageTexture.create_from_image(img)
	wand_sprite.pixel_size = 0.008
	wand_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	wand_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# Position wand in hand
	wand_sprite.position = Vector3(0.17, -0.22, -0.4)
	wand_sprite.rotation_degrees = Vector3(0, 0, -15)

	add_child(wand_sprite)

	# Add glow light at wand tip
	var tip_light = OmniLight3D.new()
	tip_light.name = "WandGlow"
	tip_light.light_color = current_spell_color
	tip_light.light_energy = 0.8
	tip_light.omni_range = 0.8
	tip_light.omni_attenuation = 2.0
	tip_light.position = Vector3(0, 0.18, 0)
	wand_sprite.add_child(tip_light)


func _draw_wand_texture(img: Image) -> void:
	var cx: int = 8
	var by: int = 44

	# Wand shaft (wood)
	var wood_color = Color(0.45, 0.3, 0.15)
	for y in range(12, by):
		for dx in range(-1, 2):
			var px: int = cx + dx
			if px >= 0 and px < 16:
				var shade: float = 0.85 + randf() * 0.15
				img.set_pixel(px, y, wood_color * shade)

	# Crystal/gem at tip
	for dy in range(-8, 3):
		for dx in range(-3, 4):
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < 4:
				var px: int = cx + dx
				var py: int = 10 + dy
				if px >= 0 and px < 16 and py >= 0:
					var brightness: float = 0.7 + (1.0 - dist / 4.0) * 0.3
					img.set_pixel(px, py, current_spell_color * brightness)

	# Crystal highlight
	img.set_pixel(cx - 1, 6, Color(1, 1, 1, 0.9))
	img.set_pixel(cx, 5, Color(1, 1, 1, 0.8))


func _animate_idle(_delta: float) -> void:
	# Gentle bob
	var bob = sin(idle_time * 1.5) * 0.008
	var sway = sin(idle_time * 0.8) * 0.3

	if arm_sprite:
		arm_sprite.position.y = -0.2 + bob

	if wand_sprite:
		wand_sprite.position.y = -0.22 + bob
		wand_sprite.rotation_degrees.z = -15 + sway

	# Pulse wand glow
	var glow = wand_sprite.get_node_or_null("WandGlow") as OmniLight3D
	if glow:
		glow.light_energy = 0.6 + sin(idle_time * 3.0) * 0.3


func _animate_cast(delta: float) -> void:
	cast_animation_time += delta

	var progress = cast_animation_time / 0.25  # 0.25 second animation

	if progress < 0.5:
		# Thrust forward
		var thrust = progress * 2.0
		if wand_sprite:
			wand_sprite.position.z = -0.4 - thrust * 0.1
			wand_sprite.rotation_degrees.x = -thrust * 20

		# Brighten glow
		var glow = wand_sprite.get_node_or_null("WandGlow") as OmniLight3D
		if glow:
			glow.light_energy = 0.8 + thrust * 3.0
	else:
		# Return
		var ret = (progress - 0.5) * 2.0
		if wand_sprite:
			wand_sprite.position.z = -0.5 + ret * 0.1
			wand_sprite.rotation_degrees.x = -20 + ret * 20

		var glow = wand_sprite.get_node_or_null("WandGlow") as OmniLight3D
		if glow:
			glow.light_energy = 3.8 - ret * 3.0

	if progress >= 1.0:
		is_casting = false
		cast_animation_time = 0.0
		if wand_sprite:
			wand_sprite.position.z = -0.4
			wand_sprite.rotation_degrees.x = 0


func play_cast_animation() -> void:
	is_casting = true
	cast_animation_time = 0.0


func set_spell_color(color: Color) -> void:
	current_spell_color = color

	# Update wand texture
	if wand_sprite:
		var img = Image.create(16, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_wand_texture(img)
		wand_sprite.texture = ImageTexture.create_from_image(img)

	# Update light color
	if wand_sprite:
		var glow = wand_sprite.get_node_or_null("WandGlow") as OmniLight3D
		if glow:
			glow.light_color = color


func set_skin_tone(skin: Color) -> void:
	skin_color = skin
	_regenerate_arm_texture()


func set_robe_color(robe: Color) -> void:
	robe_color = robe
	_regenerate_arm_texture()


func _regenerate_arm_texture() -> void:
	if arm_sprite:
		var img = Image.create(32, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_arm_texture(img)
		arm_sprite.texture = ImageTexture.create_from_image(img)
