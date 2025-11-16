extends "res://shared/animated_character.gd"
class_name Enemy

## Enemy - Basic enemy entity with AI and combat
## Server-authoritative with client visuals

signal died(enemy: Enemy)

# Enemy stats
@export var enemy_name: String = "Gahnome"
@export var max_health: float = 50.0
@export var move_speed: float = 3.0
@export var attack_range: float = 1.5
@export var attack_cooldown_time: float = 1.0  # Time between attacks
@export var detection_range: float = 15.0
@export var loot_table: Dictionary = {"wood": 2, "resin": 1}  # Drops on death (resin and wood for Gahnomes)
@export var weapon_id: String = "fists"  # Default to fists, can be changed per enemy

# Weapon data (loaded from ItemDatabase)
var weapon_data = null  # WeaponData

# Enemy state
var health: float = max_health
var is_dead: bool = false
var target_player: CharacterBody3D = null
var attack_cooldown: float = 0.0

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# Set collision layers
	collision_layer = 4  # Enemies layer (bit 2)
	collision_mask = 1 | 2  # World (1) and Players (2)

	# Load weapon data
	weapon_data = ItemDatabase.get_item(weapon_id)
	if not weapon_data:
		push_warning("[Enemy] Unknown weapon: %s, defaulting to fists" % weapon_id)
		weapon_data = ItemDatabase.get_item("fists")

	# Configure animation base class
	walk_speed = move_speed
	attack_animation_time = 0.3

	# Create visual body
	_setup_body()

	# Don't create health bar until damaged (performance optimization)
	# It will be created in take_damage() when first hit

	print("[Enemy] %s ready (Health: %d, Weapon: %s, Layer: %d, Mask: %d, Pos: %s)" % [enemy_name, max_health, weapon_data.display_name, collision_layer, collision_mask, global_position])

func _setup_body() -> void:
	# Create body container (similar to player, but smaller)
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI  # Rotate 180° to face forward (mesh is built facing +Z, but look_at uses -Z)
	add_child(body_container)

	# Scale factor for smaller gnome-like creature (2/3 of player size)
	var scale_factor: float = 0.66

	# Materials
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.45, 0.55, 0.35, 1)  # Greenish skin

	var clothes_mat = StandardMaterial3D.new()
	clothes_mat.albedo_color = Color(0.4, 0.25, 0.15, 1)  # Brown clothes

	var hair_mat = StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.7, 0.7, 0.7, 1)  # Gray hair

	# Hips
	var hips = MeshInstance3D.new()
	var hips_mesh = BoxMesh.new()
	hips_mesh.size = Vector3(0.18, 0.15, 0.1) * scale_factor
	hips.mesh = hips_mesh
	hips.material_override = clothes_mat
	hips.position = Vector3(0, 0.58 * scale_factor, 0)
	body_container.add_child(hips)

	# Torso (store reference)
	torso = MeshInstance3D.new()
	var torso_mesh = CapsuleMesh.new()
	torso_mesh.radius = 0.08 * scale_factor
	torso_mesh.height = 0.4 * scale_factor
	torso.mesh = torso_mesh
	torso.material_override = clothes_mat
	torso.position = Vector3(0, 0.75 * scale_factor, 0)
	body_container.add_child(torso)

	# Neck
	var neck = MeshInstance3D.new()
	var neck_mesh = CapsuleMesh.new()
	neck_mesh.radius = 0.03 * scale_factor
	neck_mesh.height = 0.08 * scale_factor
	neck.mesh = neck_mesh
	neck.material_override = skin_mat
	neck.position = Vector3(0, 0.92 * scale_factor, 0)
	body_container.add_child(neck)

	# Head (store reference)
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.1 * scale_factor
	head_mesh.height = 0.2 * scale_factor
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0, 0.99 * scale_factor, 0)
	body_container.add_child(head)

	# Pointy hat (gnome style!) - using prism mesh instead of cone
	var hat = MeshInstance3D.new()
	var hat_mesh = PrismMesh.new()
	hat_mesh.size = Vector3(0.22 * scale_factor, 0.25 * scale_factor, 0.22 * scale_factor)
	hat.mesh = hat_mesh
	hat.material_override = hair_mat
	hat.position = Vector3(0, 1.11 * scale_factor, 0)
	head.add_child(hat)

	# Nose
	var nose = MeshInstance3D.new()
	var nose_mesh = SphereMesh.new()
	nose_mesh.radius = 0.02 * scale_factor
	nose.mesh = nose_mesh
	nose.material_override = skin_mat
	nose.position = Vector3(0, -0.01 * scale_factor, 0.09 * scale_factor)
	head.add_child(nose)

	# Eyes
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.05, 1)  # Dark eyes

	var left_eye = MeshInstance3D.new()
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.015 * scale_factor
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.04 * scale_factor, 0.02 * scale_factor, 0.08 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.04 * scale_factor, 0.02 * scale_factor, 0.08 * scale_factor)
	head.add_child(right_eye)

	# Left Leg with pivot at hip
	var leg_mesh = CapsuleMesh.new()
	leg_mesh.radius = 0.04 * scale_factor
	leg_mesh.height = 0.35 * scale_factor

	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.06 * scale_factor, 0.58 * scale_factor, 0)  # Hip position
	body_container.add_child(left_leg)

	var left_leg_mesh = MeshInstance3D.new()
	left_leg_mesh.mesh = leg_mesh
	left_leg_mesh.material_override = clothes_mat
	left_leg_mesh.position = Vector3(0, -0.175 * scale_factor, 0)  # Offset down by half leg length
	left_leg.add_child(left_leg_mesh)

	# Right Leg with pivot at hip
	right_leg = Node3D.new()
	right_leg.position = Vector3(0.06 * scale_factor, 0.58 * scale_factor, 0)  # Hip position
	body_container.add_child(right_leg)

	var right_leg_mesh = MeshInstance3D.new()
	right_leg_mesh.mesh = leg_mesh
	right_leg_mesh.material_override = clothes_mat
	right_leg_mesh.position = Vector3(0, -0.175 * scale_factor, 0)  # Offset down by half leg length
	right_leg.add_child(right_leg_mesh)

	# Left Arm with pivot at shoulder
	var arm_mesh = CapsuleMesh.new()
	arm_mesh.radius = 0.03 * scale_factor
	arm_mesh.height = 0.3 * scale_factor

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.11 * scale_factor, 0.90 * scale_factor, 0)  # Shoulder position
	body_container.add_child(left_arm)

	var left_arm_mesh = MeshInstance3D.new()
	left_arm_mesh.mesh = arm_mesh
	left_arm_mesh.material_override = skin_mat
	left_arm_mesh.position = Vector3(0, -0.15 * scale_factor, 0)  # Offset down by half arm length
	left_arm.add_child(left_arm_mesh)

	# Right Arm with pivot at shoulder
	right_arm = Node3D.new()
	right_arm.position = Vector3(0.11 * scale_factor, 0.90 * scale_factor, 0)  # Shoulder position
	body_container.add_child(right_arm)

	var right_arm_mesh = MeshInstance3D.new()
	right_arm_mesh.mesh = arm_mesh
	right_arm_mesh.material_override = skin_mat
	right_arm_mesh.position = Vector3(0, -0.15 * scale_factor, 0)  # Offset down by half arm length
	right_arm.add_child(right_arm_mesh)

	# Set head base height for animation base class
	head_base_height = 0.99 * scale_factor


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# CLIENT-AUTHORITATIVE: All clients simulate enemies independently
	# Each client runs full AI and physics for smooth local gameplay

	# Update attack cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# Apply gravity (all clients have terrain loaded around local player)
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Client-side AI (all clients simulate)
	_update_ai(delta)

	# Move
	move_and_slide()

	# Update programmatic animations
	update_animations(delta)

## AI Update (server-only)
func _update_ai(delta: float) -> void:
	# Stunned enemies can't move or attack
	if is_stunned:
		velocity.x = 0
		velocity.z = 0
		return

	# Find nearest player if we don't have a target
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_nearest_player()

	# No target found
	if not target_player:
		# Idle - no movement
		velocity.x = 0
		velocity.z = 0
		return

	# Check if target is in range
	var distance_to_target = global_position.distance_to(target_player.global_position)

	# Out of detection range - stop chasing
	if distance_to_target > detection_range:
		target_player = null
		velocity.x = 0
		velocity.z = 0
		return

	# In attack range - attack!
	if distance_to_target <= attack_range:
		# Stop moving
		velocity.x = 0
		velocity.z = 0

		# Attack if cooldown ready
		if attack_cooldown <= 0:
			_attack_player(target_player)
			attack_cooldown = attack_cooldown_time
	else:
		# Chase player
		var direction = target_player.global_position - global_position
		direction.y = 0  # Don't move vertically

		# Only move and face if there's a horizontal distance
		if direction.length() > 0.1:
			direction = direction.normalized()
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed

			# Face target
			look_at(global_position + direction, Vector3.UP)
		else:
			# Too close horizontally, stop moving
			velocity.x = 0
			velocity.z = 0

## Find nearest player
func _find_nearest_player() -> CharacterBody3D:
	var nearest_player: CharacterBody3D = null
	var nearest_distance: float = INF

	# Get all nodes in the scene
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		# Skip if it's this enemy or another enemy
		if player == self or player.is_in_group("enemies"):
			continue

		if player is CharacterBody3D:
			var distance = global_position.distance_to(player.global_position)
			if distance < nearest_distance and distance <= detection_range:
				nearest_distance = distance
				nearest_player = player

	return nearest_player

## Attack a player
func _attack_player(player: CharacterBody3D) -> void:
	print("[Enemy] %s attacks player with %s!" % [enemy_name, weapon_data.display_name])

	# Start attack animation
	start_attack_animation()

	# Calculate knockback direction
	var knockback_dir = (player.global_position - global_position).normalized()

	# Use weapon stats for damage and knockback
	var damage = weapon_data.damage
	var knockback = weapon_data.knockback

	# Apply damage (if player has take_damage method)
	if player.has_method("take_damage"):
		player.take_damage(damage, get_instance_id(), knockback_dir)

## Take damage
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	var final_damage = damage

	# Apply stun damage multiplier if stunned
	if is_stunned:
		final_damage *= STUN_DAMAGE_MULTIPLIER
		print("[Enemy] %s taking extra damage while stunned! (%.1fx multiplier)" % [enemy_name, STUN_DAMAGE_MULTIPLIER])

	health -= final_damage
	print("[Enemy] %s took %.1f damage, health: %.1f, knockback: %.1f" % [enemy_name, final_damage, health, knockback])

	# Create health bar on first damage (lazy loading for performance)
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(1.2)  # Position above enemy head

	# Update health bar
	if health_bar:
		health_bar.update_health(health, max_health)

	# Apply knockback (horizontal only, don't launch enemies into the air)
	if knockback > 0 and direction.length() > 0:
		var knockback_dir = direction.normalized()
		knockback_dir.y = 0  # Keep knockback horizontal
		knockback_dir = knockback_dir.normalized()

		# Apply knockback to velocity
		velocity += knockback_dir * knockback
		print("[Enemy] Applied knockback: %s (magnitude: %.1f)" % [knockback_dir * knockback, knockback])

	if health <= 0:
		health = 0
		_die()

## Handle death
func _die() -> void:
	if is_dead:
		return

	is_dead = true
	print("[Enemy] %s died!" % enemy_name)

	# Emit died signal
	died.emit(self)

	# Drop loot
	if multiplayer.is_server():
		_drop_loot()

	# Play death animation (programmatic fade/fall)
	if body_container:
		var tween = create_tween()
		tween.tween_property(body_container, "position:y", -1.0, 1.0)
		tween.parallel().tween_property(body_container, "rotation:x", PI / 2, 1.0)
		tween.tween_callback(queue_free)

## Drop loot on death (SERVER-SIDE ONLY)
func _drop_loot() -> void:
	if loot_table.is_empty():
		return

	print("[Enemy] Dropping loot: %s" % loot_table)

	# Generate network IDs for each loot item
	var network_ids: Array = []
	for resource_type in loot_table:
		var amount: int = loot_table[resource_type]
		for i in amount:
			# Use server time and enemy info for unique IDs
			var net_id = "%s_%d_%d" % [enemy_name, Time.get_ticks_msec(), i]
			network_ids.append(net_id)

	# Spawn resource drops at enemy position
	var pos_array = [global_position.x, global_position.y, global_position.z]
	NetworkManager.rpc_spawn_resource_drops.rpc(loot_table, pos_array, network_ids)

