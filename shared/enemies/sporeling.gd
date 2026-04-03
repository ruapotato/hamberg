extends "res://shared/enemies/enemy.gd"

## Sporeling - Bioluminescent fungal creature of the dark forest
## Larger, more patient, uses spore cloud attacks
## Different AI: stalks longer, has area-of-effect damage

# Spore cloud attack - defensive reaction when hit
const SPORE_CLOUD_SCENE = preload("res://shared/effects/spore_cloud.tscn")
var spore_attack_cooldown: float = 0.0
const SPORE_ATTACK_COOLDOWN_TIME: float = 6.0  # 6 seconds between spore attacks
const SPORE_ATTACK_CHANCE: float = 0.5  # 50% chance to release spores when hit

func _ready() -> void:
	# Override stats for Sporeling
	enemy_name = "Sporeling"
	max_health = 100.0
	move_speed = 2.0  # Slower movement
	charge_speed = 3.5  # Slower charge
	strafe_speed = 1.2
	attack_range = 1.8  # Longer reach (larger creature)
	attack_cooldown_time = 1.8  # Slower attacks
	windup_time = 0.7  # Longer telegraph
	detection_range = 22.0  # Can see further in the dark
	preferred_distance = 8.0  # Prefers to stay further away
	throw_range = 0.0  # No rock throwing - uses spore attack instead
	throw_min_range = 0.0
	loot_table = {"glowing_spore": 3, "fungal_essence": 1}
	weapon_id = "sporeling_fists"

	# Sporeling resistances - fungal creature
	# Very resistant to poison (fungi are natural), very weak to fire (burns easily)
	damage_resistances = {
		WeaponData.DamageType.SLASH: 0.9,    # 10% resistant (spongy body)
		WeaponData.DamageType.BLUNT: 1.2,    # 20% weak to blunt (squishy)
		WeaponData.DamageType.PIERCE: 0.8,   # 20% resistant (holes don't hurt fungi)
		WeaponData.DamageType.FIRE: 1.5,     # 50% WEAK to fire (very burnable!)
		WeaponData.DamageType.ICE: 1.0,      # Neutral to ice
		WeaponData.DamageType.POISON: 0.5,   # 50% resistant to poison (fungi immunity)
	}

	# Call parent ready
	super._ready()

	# Higher aggression but more patient
	aggression = randf_range(0.5, 0.9)
	patience = randf_range(0.6, 0.9)  # Much more patient

	health = max_health

## Override body setup for bioluminescent fungal billboard sprite (Paper Mario style)
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	# Directional Billboard Sprite3D (Paper Mario style)
	var sprite = DirectionalSpriteScript.new()
	sprite.name = "Sprite"
	sprite.pixel_size = 0.025
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var sporeling_tex = _create_sprite_texture()
	sprite.texture = sporeling_tex
	sprite.set_textures_4dir(sporeling_tex, sporeling_tex, sporeling_tex, sporeling_tex)
	# Sporeling is larger: 64px * 0.025 = 1.6 units, center at half
	sprite.position = Vector3(0, 0.8, 0)
	body_container.add_child(sprite)

	head_base_height = 0.0  # No 3D head to bob

## Create a procedural 64x64 mushroom/sporeling sprite texture (purple/red bioluminescent)
func _create_sprite_texture() -> ImageTexture:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Transparent background

	var cap_color = Color(0.35, 0.1, 0.45, 1.0)        # Deep purple cap
	var cap_highlight = Color(0.5, 0.15, 0.6, 1.0)      # Lighter purple highlight
	var body_color = Color(0.15, 0.2, 0.25, 1.0)        # Dark blue-gray body
	var eye_color = Color(0.8, 0.2, 0.8, 1.0)           # Magenta glowing eyes
	var spot_color = Color(0.0, 0.8, 0.4, 1.0)          # Bright green spore spots
	var tendril_color = Color(0.12, 0.25, 0.22, 1.0)    # Dark teal tendrils

	# Mushroom cap dome (rows 2-22, wide dome shape)
	for y in range(2, 23):
		var dy = (y - 12.0) / 10.0
		var half_w = int(18.0 * sqrt(max(0, 1.0 - dy * dy)))
		if y < 12:
			half_w = int(half_w * 0.85)  # Narrower at top of dome
		for x in range(32 - half_w, 32 + half_w):
			# Add highlight near center-top
			if y < 10 and abs(x - 32) < 6:
				img.set_pixel(x, y, cap_highlight)
			else:
				img.set_pixel(x, y, cap_color)

	# Cap rim / underside (rows 20-24, flat bottom edge)
	for y in range(20, 25):
		var half_w = int(16.0 - (y - 20) * 2.5)
		if half_w < 2:
			half_w = 2
		for x in range(32 - half_w, 32 + half_w):
			img.set_pixel(x, y, cap_color.darkened(0.3))

	# Glowing spots on cap
	var spots = [Vector2i(24, 8), Vector2i(38, 10), Vector2i(28, 14), Vector2i(36, 6), Vector2i(32, 4)]
	for s in spots:
		if s.x >= 0 and s.x < 64 and s.y >= 0 and s.y < 64:
			img.set_pixel(s.x, s.y, spot_color)
			if s.x + 1 < 64:
				img.set_pixel(s.x + 1, s.y, spot_color)
			if s.y + 1 < 64:
				img.set_pixel(s.x, s.y + 1, spot_color)

	# Multiple glowing eyes under cap (row 22-24)
	var eye_xs = [26, 28, 35, 37]
	for ex in eye_xs:
		img.set_pixel(ex, 22, eye_color)
		img.set_pixel(ex, 23, eye_color)

	# Bulbous body / stalk (rows 24-46)
	for y in range(24, 47):
		var progress = (y - 24.0) / 22.0
		# Bulges in the middle, narrower at top and bottom
		var bulge = sin(progress * PI) * 4.0
		var half_w = int(5.0 + bulge)
		for x in range(32 - half_w, 32 + half_w):
			img.set_pixel(x, y, body_color)

	# Glowing spore spots on body
	var body_spots = [Vector2i(30, 30), Vector2i(35, 35), Vector2i(29, 40), Vector2i(34, 28)]
	for s in body_spots:
		img.set_pixel(s.x, s.y, spot_color)

	# Tendril arms (rows 28-40, thin wispy arms)
	for y in range(28, 41):
		var progress = (y - 28.0) / 12.0
		# Left tendril curves outward
		var lx = int(26 - progress * 8)
		for dx in range(0, 2):
			if lx + dx >= 0:
				img.set_pixel(lx + dx, y, tendril_color)
		# Right tendril curves outward
		var rx = int(37 + progress * 8)
		for dx in range(0, 2):
			if rx + dx < 64:
				img.set_pixel(rx + dx, y, tendril_color)

	# Tendril legs (rows 47-60, multiple thin legs)
	var leg_offsets = [-5, -2, 2, 5]
	for lo in leg_offsets:
		for y in range(47, 61):
			var spread = (y - 47.0) / 13.0 * lo * 0.5
			var lx = int(32 + lo + spread)
			if lx >= 0 and lx < 63:
				img.set_pixel(lx, y, tendril_color)
				img.set_pixel(lx + 1, y, tendril_color)

	var tex = ImageTexture.create_from_image(img)
	return tex

## Override telegraph to use sprite tint (no 3D arms to swing)
func _set_windup_telegraph(enabled: bool) -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	if enabled:
		# Tint with spore-green warning
		_set_body_tint(Color(0.4, 1.0, 0.4, 1.0))
	else:
		_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

## Override attack swing animation (sprite squash-and-stretch)
func _play_attack_swing() -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	# Quick lunge forward effect via scale squash
	windup_tween = create_tween()
	windup_tween.tween_property(body_container, "scale", Vector3(1.2, 0.85, 1.2), 0.1)
	windup_tween.tween_property(body_container, "scale", Vector3.ONE, 0.3)

	_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

## Override physics process to handle spore attack cooldown
func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	# Update spore attack cooldown
	if spore_attack_cooldown > 0:
		spore_attack_cooldown -= delta

## Override take_damage to potentially release spore cloud as defense
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO, damage_type: int = -1, attacker_peer_id: int = 0) -> void:
	# Call parent damage handling first
	super.take_damage(damage, knockback, direction, damage_type, attacker_peer_id)

	# Check if we should release a defensive spore cloud
	if not is_dead and spore_attack_cooldown <= 0 and randf() < SPORE_ATTACK_CHANCE:
		_do_spore_attack()

## Spawn a spore cloud at current position as defensive reaction
func _do_spore_attack() -> void:
	# Set cooldown
	spore_attack_cooldown = SPORE_ATTACK_COOLDOWN_TIME

	# Brief green flash when releasing spores
	_set_body_tint(Color(0.4, 1.0, 0.4, 1.0))
	get_tree().create_timer(0.3).timeout.connect(func(): _set_body_tint(Color(1.0, 1.0, 1.0, 1.0)))

	# Spawn the spore cloud immediately at our position
	if SPORE_CLOUD_SCENE:
		var spore_cloud = SPORE_CLOUD_SCENE.instantiate()
		# Pass network info for proper damage sync
		spore_cloud.is_host = is_host
		spore_cloud.spawner_network_id = network_id
		# Add to the world, not to us (so it stays when we move)
		get_parent().add_child(spore_cloud)
		spore_cloud.global_position = global_position
		spore_cloud.global_position.y += 0.5  # Slightly above ground

		print("[Sporeling] Released defensive spore cloud at %s (is_host: %s)" % [global_position, is_host])
