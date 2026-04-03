extends "res://shared/animals/passive_animal.gd"

## Unicorn Sheep - Fluffy wool-covered animal with a single ram's horn
## Found in meadow biomes
## Peaceful until attacked - then it fights back with its horn!
## Drops raw mutton when killed

# Combat state
var is_provoked: bool = false
var provoke_timer: float = 0.0
const PROVOKE_DURATION: float = 15.0  # How long it stays angry
var target_attacker: CharacterBody3D = null

# Horn attack parameters
var horn_damage: float = 12.0
var horn_knockback: float = 8.0
var charge_speed_sheep: float = 6.0
var sheep_attack_range: float = 1.5
var sheep_attack_cooldown: float = 1.5
var current_attack_cooldown: float = 0.0

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with sheep-specific values
	enemy_name = "Unicorn Sheep"
	max_health = 40.0  # Tougher than regular sheep
	move_speed = 2.8
	strafe_speed = 2.2
	loot_table = {"raw_mutton": 2}

	# Unicorn sheep uses horn as weapon
	weapon_id = "fists"  # We'll handle damage directly

	print("[Sheep] Unicorn sheep ready (network_id=%d)" % network_id)

## Build sheep body - 2D billboard sprite (Paper Mario style)
func _setup_body() -> void:
	# Check if BodyContainer already exists in the scene (from TSCN)
	var existing_container = get_node_or_null("BodyContainer")
	if existing_container and existing_container.get_child_count() > 0:
		body_container = existing_container
		head_base_height = 0.5 * 0.85
		print("[Sheep] Using custom mesh from TSCN")
		return

	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	var sprite = DirectionalSpriteScript.new()
	sprite.name = "BodySprite"
	sprite.pixel_size = 0.025
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tex_side = TextureGenerator.generate_sheep_texture("side")
	var tex_front = TextureGenerator.generate_sheep_texture("front")
	var tex_back = TextureGenerator.generate_sheep_texture("back")
	sprite.texture = tex_side
	sprite.set_textures_4dir(tex_front, tex_back, tex_side, tex_side)

	# Position sprite so bottom is at ground level
	var sprite_height = sprite.texture.get_height() if sprite.texture else 32
	sprite.position.y = sprite_height * sprite.pixel_size * 0.5
	body_container.add_child(sprite)

	head_base_height = 0.5 * 0.85

## Override take_damage to become aggressive when attacked
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO, damage_type: int = -1, attacker_peer_id: int = 0) -> void:
	# Call parent damage handling
	super.take_damage(damage, knockback, direction, damage_type, attacker_peer_id)

	# Become provoked - fight back!
	if not is_provoked and is_host:
		is_provoked = true
		provoke_timer = PROVOKE_DURATION
		print("[Sheep] Unicorn sheep is angry! It's fighting back!")

		# Find who attacked us (nearest player)
		target_attacker = _find_nearest_player()

## Override AI update to handle combat when provoked
func _update_ai(delta: float) -> void:
	if is_stunned:
		velocity.x = 0
		velocity.z = 0
		return

	# Update attack cooldown
	if current_attack_cooldown > 0:
		current_attack_cooldown -= delta

	# Handle provoked state
	if is_provoked:
		provoke_timer -= delta
		if provoke_timer <= 0:
			is_provoked = false
			target_attacker = null
			print("[Sheep] Unicorn sheep calms down")
		else:
			_update_combat(delta)
			return

	# Normal passive behavior - update flee timer or idle
	if flee_timer > 0:
		flee_timer -= delta
		_update_fleeing(delta)
	else:
		_update_idle(delta)

## Combat behavior when provoked
func _update_combat(delta: float) -> void:
	# Find or validate target
	if not target_attacker or not is_instance_valid(target_attacker):
		target_attacker = _find_nearest_player()
		if not target_attacker:
			is_provoked = false
			return

	var distance = global_position.distance_to(target_attacker.global_position)

	# If target is too far, lose aggro
	if distance > 20.0:
		is_provoked = false
		target_attacker = null
		return

	# Close enough to attack?
	if distance <= sheep_attack_range:
		# Stop and attack!
		velocity.x = 0
		velocity.z = 0
		_face_attacker()

		if current_attack_cooldown <= 0:
			_do_horn_attack()
			current_attack_cooldown = sheep_attack_cooldown
	else:
		# Charge at the attacker!
		var direction = target_attacker.global_position - global_position
		direction.y = 0
		direction = direction.normalized()

		velocity.x = direction.x * charge_speed_sheep
		velocity.z = direction.z * charge_speed_sheep
		_face_attacker()

	# Use charging/attacking state for animation sync
	if distance <= sheep_attack_range:
		ai_state = AIState.ATTACKING
	else:
		ai_state = AIState.CHARGING

## Face the attacker
func _face_attacker() -> void:
	if not target_attacker:
		return
	var direction = target_attacker.global_position - global_position
	direction.y = 0
	if direction.length() > 0.1:
		look_at(global_position + direction.normalized(), Vector3.UP)

## Do a horn attack
func _do_horn_attack() -> void:
	print("[Sheep] Unicorn sheep attacks with its horn!")

	# Play attack sound
	SoundManager.play_sound_varied("sword_swing", global_position)

	# Check if local player is in range
	var local_player = _get_local_player()
	if not local_player:
		return

	var dist = global_position.distance_to(local_player.global_position)
	if dist > sheep_attack_range * 1.5:
		return  # Too far

	# Apply damage to local player
	var knockback_dir = (local_player.global_position - global_position).normalized()

	if local_player.has_method("take_damage"):
		print("[Sheep] Dealing %.1f horn damage to player" % horn_damage)
		local_player.take_damage(horn_damage, -1, knockback_dir * horn_knockback)

## Find the nearest player (for targeting) - uses cached player list
func _find_nearest_player() -> CharacterBody3D:
	var players = EnemyAI._get_cached_players(get_tree())
	var nearest_player: CharacterBody3D = null
	var nearest_dist: float = INF

	for player in players:
		if not is_instance_valid(player):
			continue
		if player == self or player.is_in_group("enemies"):
			continue
		var dist = global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_player = player

	return nearest_player

## Get local player for damage checks
func _get_local_player() -> CharacterBody3D:
	var my_peer_id = multiplayer.get_unique_id()
	var player_name = "Player_" + str(my_peer_id)
	var world = get_parent()
	if world:
		return world.get_node_or_null(player_name)
	return null
