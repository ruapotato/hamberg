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

## Build sheep body - fluffy white wool, black face and legs, with a single ram's horn!
## If BodyContainer exists in TSCN with children, uses that mesh instead
func _setup_body() -> void:
	# Check if BodyContainer already exists in the scene (from TSCN)
	var existing_container = get_node_or_null("BodyContainer")
	if existing_container and existing_container.get_child_count() > 0:
		# Use the mesh from TSCN
		body_container = existing_container
		head_base_height = 0.5 * 0.85  # Default sheep height
		print("[Sheep] Using custom mesh from TSCN")
		return

	# Create procedural mesh if no custom mesh provided
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI  # Face -Z direction (forward in Godot)
	add_child(body_container)

	var scale_factor: float = 0.85

	# Sheep materials
	var wool_mat = StandardMaterial3D.new()
	wool_mat.albedo_color = Color(0.95, 0.95, 0.9, 1)  # Off-white wool

	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.2, 0.18, 0.15, 1)  # Dark brown/black face

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.1, 0.08, 0.05, 1)  # Dark eyes

	# Horn material - ivory/cream colored with slight gold tint
	var horn_mat = StandardMaterial3D.new()
	horn_mat.albedo_color = Color(0.95, 0.9, 0.75, 1)  # Ivory with gold tint
	horn_mat.metallic = 0.1
	horn_mat.roughness = 0.6

	# Woolly body (bumpy sphere cluster)
	torso = MeshInstance3D.new()
	var body_mesh = SphereMesh.new()
	body_mesh.radius = 0.25 * scale_factor
	body_mesh.height = 0.45 * scale_factor
	torso.mesh = body_mesh
	torso.material_override = wool_mat
	torso.position = Vector3(0, 0.4 * scale_factor, 0)
	torso.scale = Vector3(1, 0.85, 1.2)
	body_container.add_child(torso)

	# Add wool bumps for fluffy appearance
	var bump_mesh = SphereMesh.new()
	bump_mesh.radius = 0.08 * scale_factor
	bump_mesh.height = 0.12 * scale_factor

	var bump_positions = [
		Vector3(0.15, 0.1, 0.1) * scale_factor,
		Vector3(-0.15, 0.1, 0.1) * scale_factor,
		Vector3(0.12, 0.15, -0.1) * scale_factor,
		Vector3(-0.12, 0.15, -0.1) * scale_factor,
		Vector3(0, 0.2, 0) * scale_factor,
		Vector3(0.1, 0.05, 0.15) * scale_factor,
		Vector3(-0.1, 0.05, 0.15) * scale_factor,
	]

	for pos in bump_positions:
		var bump = MeshInstance3D.new()
		bump.mesh = bump_mesh
		bump.material_override = wool_mat
		bump.position = pos
		torso.add_child(bump)

	# Head (dark-faced sheep)
	head = MeshInstance3D.new()
	var head_mesh = CapsuleMesh.new()
	head_mesh.radius = 0.08 * scale_factor
	head_mesh.height = 0.16 * scale_factor
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0, 0.5 * scale_factor, 0.28 * scale_factor)
	head.rotation.x = PI / 2
	body_container.add_child(head)

	# Wool tuft on top of head
	var head_wool = MeshInstance3D.new()
	var head_wool_mesh = SphereMesh.new()
	head_wool_mesh.radius = 0.06 * scale_factor
	head_wool_mesh.height = 0.08 * scale_factor
	head_wool.mesh = head_wool_mesh
	head_wool.material_override = wool_mat
	head_wool.position = Vector3(0, 0.06 * scale_factor, -0.02 * scale_factor)
	head.add_child(head_wool)

	# === SINGLE RAM'S HORN (UNICORN STYLE) ===
	# The horn spirals up and forward from the center of the forehead
	var horn_container = Node3D.new()
	horn_container.name = "HornContainer"
	horn_container.position = Vector3(0, 0.08 * scale_factor, 0.02 * scale_factor)
	horn_container.rotation.x = -0.3  # Tilt forward slightly
	head.add_child(horn_container)

	# Create a ram-like spiral horn using multiple cone segments
	# Base of horn (thickest part)
	var horn_base = MeshInstance3D.new()
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = 0.025 * scale_factor
	base_mesh.bottom_radius = 0.035 * scale_factor
	base_mesh.height = 0.08 * scale_factor
	horn_base.mesh = base_mesh
	horn_base.material_override = horn_mat
	horn_base.position = Vector3(0, 0.04 * scale_factor, 0)
	horn_container.add_child(horn_base)

	# First curve segment
	var horn_mid1 = MeshInstance3D.new()
	var mid1_mesh = CylinderMesh.new()
	mid1_mesh.top_radius = 0.018 * scale_factor
	mid1_mesh.bottom_radius = 0.025 * scale_factor
	mid1_mesh.height = 0.07 * scale_factor
	horn_mid1.mesh = mid1_mesh
	horn_mid1.material_override = horn_mat
	horn_mid1.position = Vector3(0.02 * scale_factor, 0.08 * scale_factor, 0.01 * scale_factor)
	horn_mid1.rotation.z = -0.3  # Curve outward
	horn_mid1.rotation.x = -0.2  # Curve forward
	horn_container.add_child(horn_mid1)

	# Second curve segment (spiraling)
	var horn_mid2 = MeshInstance3D.new()
	var mid2_mesh = CylinderMesh.new()
	mid2_mesh.top_radius = 0.012 * scale_factor
	mid2_mesh.bottom_radius = 0.018 * scale_factor
	mid2_mesh.height = 0.06 * scale_factor
	horn_mid2.mesh = mid2_mesh
	horn_mid2.material_override = horn_mat
	horn_mid2.position = Vector3(0.05 * scale_factor, 0.12 * scale_factor, 0.03 * scale_factor)
	horn_mid2.rotation.z = -0.5  # More curve
	horn_mid2.rotation.x = -0.3
	horn_container.add_child(horn_mid2)

	# Third curve segment
	var horn_mid3 = MeshInstance3D.new()
	var mid3_mesh = CylinderMesh.new()
	mid3_mesh.top_radius = 0.008 * scale_factor
	mid3_mesh.bottom_radius = 0.012 * scale_factor
	mid3_mesh.height = 0.05 * scale_factor
	horn_mid3.mesh = mid3_mesh
	horn_mid3.material_override = horn_mat
	horn_mid3.position = Vector3(0.08 * scale_factor, 0.14 * scale_factor, 0.05 * scale_factor)
	horn_mid3.rotation.z = -0.7  # Even more curve
	horn_mid3.rotation.x = -0.4
	horn_container.add_child(horn_mid3)

	# Tip of horn (pointed)
	var horn_tip = MeshInstance3D.new()
	var tip_mesh = CylinderMesh.new()
	tip_mesh.top_radius = 0.002 * scale_factor
	tip_mesh.bottom_radius = 0.008 * scale_factor
	tip_mesh.height = 0.04 * scale_factor
	horn_tip.mesh = tip_mesh
	horn_tip.material_override = horn_mat
	horn_tip.position = Vector3(0.1 * scale_factor, 0.15 * scale_factor, 0.07 * scale_factor)
	horn_tip.rotation.z = -0.9  # Final curve
	horn_tip.rotation.x = -0.5
	horn_container.add_child(horn_tip)

	# Snout
	var snout = MeshInstance3D.new()
	var snout_mesh = BoxMesh.new()
	snout_mesh.size = Vector3(0.06, 0.04, 0.06) * scale_factor
	snout.mesh = snout_mesh
	snout.material_override = skin_mat
	snout.position = Vector3(0, -0.02 * scale_factor, 0.1 * scale_factor)
	head.add_child(snout)

	# Eyes
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.015 * scale_factor
	eye_mesh.height = 0.03 * scale_factor

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.05 * scale_factor, 0.02 * scale_factor, 0.06 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.05 * scale_factor, 0.02 * scale_factor, 0.06 * scale_factor)
	head.add_child(right_eye)

	# Ears (horizontal floppy)
	var ear_mesh = CapsuleMesh.new()
	ear_mesh.radius = 0.02 * scale_factor
	ear_mesh.height = 0.08 * scale_factor

	var left_ear = MeshInstance3D.new()
	left_ear.mesh = ear_mesh
	left_ear.material_override = skin_mat
	left_ear.position = Vector3(-0.08 * scale_factor, 0.02 * scale_factor, 0)
	left_ear.rotation.z = PI / 2
	head.add_child(left_ear)

	var right_ear = MeshInstance3D.new()
	right_ear.mesh = ear_mesh
	right_ear.material_override = skin_mat
	right_ear.position = Vector3(0.08 * scale_factor, 0.02 * scale_factor, 0)
	right_ear.rotation.z = PI / 2
	head.add_child(right_ear)

	# Legs (4 thin dark legs)
	var leg_mesh = CapsuleMesh.new()
	leg_mesh.radius = 0.025 * scale_factor
	leg_mesh.height = 0.25 * scale_factor

	# Front left leg
	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.1 * scale_factor, 0.25 * scale_factor, 0.12 * scale_factor)
	body_container.add_child(left_leg)

	var fl_leg_mesh = MeshInstance3D.new()
	fl_leg_mesh.mesh = leg_mesh
	fl_leg_mesh.material_override = skin_mat
	fl_leg_mesh.position = Vector3(0, -0.125 * scale_factor, 0)
	left_leg.add_child(fl_leg_mesh)

	# Front right leg
	right_leg = Node3D.new()
	right_leg.position = Vector3(0.1 * scale_factor, 0.25 * scale_factor, 0.12 * scale_factor)
	body_container.add_child(right_leg)

	var fr_leg_mesh = MeshInstance3D.new()
	fr_leg_mesh.mesh = leg_mesh
	fr_leg_mesh.material_override = skin_mat
	fr_leg_mesh.position = Vector3(0, -0.125 * scale_factor, 0)
	right_leg.add_child(fr_leg_mesh)

	# Back left leg (stored in class variable for animation)
	back_left_leg = Node3D.new()
	back_left_leg.position = Vector3(-0.1 * scale_factor, 0.25 * scale_factor, -0.15 * scale_factor)
	body_container.add_child(back_left_leg)

	var bl_leg_mesh = MeshInstance3D.new()
	bl_leg_mesh.mesh = leg_mesh
	bl_leg_mesh.material_override = skin_mat
	bl_leg_mesh.position = Vector3(0, -0.125 * scale_factor, 0)
	back_left_leg.add_child(bl_leg_mesh)

	# Back right leg (stored in class variable for animation)
	back_right_leg = Node3D.new()
	back_right_leg.position = Vector3(0.1 * scale_factor, 0.25 * scale_factor, -0.15 * scale_factor)
	body_container.add_child(back_right_leg)

	var br_leg_mesh = MeshInstance3D.new()
	br_leg_mesh.mesh = leg_mesh
	br_leg_mesh.material_override = skin_mat
	br_leg_mesh.position = Vector3(0, -0.125 * scale_factor, 0)
	back_right_leg.add_child(br_leg_mesh)

	# Small tail (wool puff)
	var tail = MeshInstance3D.new()
	var tail_mesh = SphereMesh.new()
	tail_mesh.radius = 0.05 * scale_factor
	tail_mesh.height = 0.07 * scale_factor
	tail.mesh = tail_mesh
	tail.material_override = wool_mat
	tail.position = Vector3(0, 0.42 * scale_factor, -0.25 * scale_factor)
	body_container.add_child(tail)

	head_base_height = 0.5 * scale_factor

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
