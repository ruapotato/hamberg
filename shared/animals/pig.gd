extends "res://shared/animals/passive_animal.gd"

## Flying Pig - Whimsical winged pig that walks normally but flies when threatened
## Found in meadow biomes
## Drops raw pork when killed

# Wing references for animation
var left_wing: Node3D = null
var right_wing: Node3D = null

# Flying state
var is_flying: bool = false
var fly_timer: float = 0.0
const MAX_FLY_TIME: float = 8.0  # Max seconds in air before must land
const FLY_COOLDOWN: float = 3.0  # Seconds on ground before can fly again
var fly_cooldown_timer: float = 0.0
var target_altitude: float = 5.0

# Animation timers
var bob_timer: float = 0.0
var bob_speed: float = 2.0
var bob_amount: float = 0.3
var wing_flap_speed: float = 8.0

# Ground movement
var ground_move_speed: float = 2.0

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with pig-specific values
	enemy_name = "Flying Pig"
	max_health = 35.0
	move_speed = ground_move_speed  # Normal ground speed
	strafe_speed = 2.0
	loot_table = {"raw_pork": 3, "pig_leather": 2}

	print("[Pig] Flying pig ready (network_id=%d)" % network_id)

## Build pig body - 2D billboard sprite (Paper Mario style)
func _setup_body() -> void:
	# Check if BodyContainer already exists in the scene (from TSCN)
	var existing_container = get_node_or_null("BodyContainer")
	if existing_container and existing_container.get_child_count() > 0:
		body_container = existing_container
		head_base_height = 0.4 * 0.8
		print("[Pig] Using custom mesh from TSCN")
		return

	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	var sprite = DirectionalSpriteScript.new()
	sprite.name = "BodySprite"
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Try aalib sprites first, fall back to procedural
	var aalib = SpriteLoader.load_character_sprites("pig")
	if aalib.size() > 0 and aalib.get("front") != null:
		sprite.pixel_size = 0.0025  # 639px * 0.0025 = ~1.6 units tall
		sprite.texture = aalib.get("left", aalib["front"])
		sprite.set_textures_4dir(
			aalib["front"],
			aalib["back"],
			aalib.get("left", aalib["front"]),
			aalib.get("right", aalib["front"])
		)
	else:
		sprite.pixel_size = 0.025
		var tex_side = TextureGenerator.generate_pig_texture("side")
		var tex_front = TextureGenerator.generate_pig_texture("front")
		var tex_back = TextureGenerator.generate_pig_texture("back")
		sprite.texture = tex_side
		sprite.set_textures_4dir(tex_front, tex_back, tex_side, tex_side)

	# Position sprite so bottom is at ground level
	var sprite_height = sprite.texture.get_height() if sprite.texture else 32
	sprite.position.y = sprite_height * sprite.pixel_size * 0.5
	body_container.add_child(sprite)

	head_base_height = 0.4 * 0.8

## Override physics process for flying state and wing animation
func _physics_process(delta: float) -> void:
	# Update flying state timers
	if is_flying:
		fly_timer += delta
		# Must land after max fly time
		if fly_timer >= MAX_FLY_TIME:
			_start_landing()
	else:
		# Cooldown before can fly again
		if fly_cooldown_timer > 0:
			fly_cooldown_timer -= delta

	# Call parent physics
	super._physics_process(delta)

	# Animate wings based on flying state
	bob_timer += delta * wing_flap_speed
	if left_wing and right_wing:
		if is_flying:
			# Fast flapping when flying
			var flap_angle = sin(bob_timer) * 0.6
			left_wing.rotation.z = flap_angle + 0.3
			right_wing.rotation.z = -flap_angle - 0.3
		else:
			# Wings folded when on ground
			left_wing.rotation.z = 0.8  # Folded up
			right_wing.rotation.z = -0.8

## Start flying (called when hit)
func _start_flying() -> void:
	if is_flying or fly_cooldown_timer > 0:
		return
	is_flying = true
	fly_timer = 0.0
	target_altitude = global_position.y + randf_range(4.0, 7.0)
	move_speed = 4.5  # Faster when flying
	print("[Pig] Taking flight!")

## Start landing (called when fly time expires)
func _start_landing() -> void:
	is_flying = false
	fly_cooldown_timer = FLY_COOLDOWN
	move_speed = ground_move_speed
	print("[Pig] Landing...")

## Override take_damage to trigger flight
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO, damage_type: int = -1, attacker_peer_id: int = 0) -> void:
	super.take_damage(damage, knockback, direction, damage_type, attacker_peer_id)
	# Take flight when hit!
	if not is_dead:
		_start_flying()

## Override idle behavior - walk on ground normally
func _update_idle(delta: float) -> void:
	if is_flying:
		_update_flying_idle(delta)
	else:
		# Normal ground wandering (from parent passive_animal)
		super._update_idle(delta)

## Flying idle - hover around
func _update_flying_idle(delta: float) -> void:
	# Gentle random movement while hovering
	if wander_timer <= 0:
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle))
		wander_timer = randf_range(2.0, 4.0)
	else:
		wander_timer -= delta

	velocity.x = wander_direction.x * move_speed * 0.5
	velocity.z = wander_direction.z * move_speed * 0.5

	# Maintain altitude with bobbing
	var bob_offset = sin(bob_timer * bob_speed * 0.3) * bob_amount
	var height_diff = (target_altitude + bob_offset) - global_position.y
	velocity.y = height_diff * 2.0

	if velocity.length() > 0.1:
		_face_movement()

	ai_state = AIState.IDLE

## Override fleeing to fly away when hit
func _update_fleeing(delta: float) -> void:
	if is_flying:
		_update_flying_flee(delta)
	else:
		# Ground fleeing
		super._update_fleeing(delta)

## Flying flee - fly away fast and high
func _update_flying_flee(delta: float) -> void:
	# Update direction change timer
	direction_change_timer -= delta

	if direction_change_timer <= 0:
		direction_change_timer = randf_range(MIN_DIRECTION_CHANGE_TIME, MAX_DIRECTION_CHANGE_TIME)

		# Fly away from player
		if flee_from_player and is_instance_valid(flee_from_player):
			var away_dir = global_position - flee_from_player.global_position
			away_dir.y = 0
			if away_dir.length() > 0.1:
				flee_target = away_dir.normalized()
			else:
				var angle = randf() * TAU
				flee_target = Vector3(cos(angle), 0, sin(angle))

		# Add random angle offset
		var angle_offset = randf_range(-DIRECTION_CHANGE_ANGLE, DIRECTION_CHANGE_ANGLE)
		flee_target = flee_target.rotated(Vector3.UP, angle_offset)

		# Fly higher when fleeing!
		target_altitude = global_position.y + randf_range(2.0, 4.0)
		target_altitude = min(target_altitude, 12.0)  # Cap max altitude

	# Fly in flee direction
	var flee_speed = move_speed * FLEE_SPEED_MULTIPLIER
	velocity.x = flee_target.x * flee_speed
	velocity.z = flee_target.z * flee_speed

	# Maintain altitude with bobbing
	var bob_offset = sin(bob_timer * bob_speed * 0.3) * bob_amount
	var height_diff = (target_altitude + bob_offset) - global_position.y
	velocity.y = height_diff * 3.0

	_face_movement()

	ai_state = AIState.RETREATING
