extends "res://shared/enemies/enemy.gd"

## Zombie - Undead enemy that spawns in all biomes
## Uses 3D procedural mesh body (green-skinned humanoid)
## Different zombie types have different stats and appearances:
##   walker, runner, brute, mage_zombie, exploder

# Zombie type - set BEFORE adding to tree (used in _ready)
var zombie_type: String = "walker"

# Type-specific stats: {hp, speed, charge_speed, damage, attack_range}
const ZOMBIE_STATS = {
	"walker": { "hp": 60.0, "speed": 3.0, "charge_speed": 5.0, "damage": 10.0, "attack_range": 1.0 },
	"runner": { "hp": 40.0, "speed": 6.0, "charge_speed": 8.0, "damage": 8.0, "attack_range": 0.9 },
	"brute": { "hp": 180.0, "speed": 1.5, "charge_speed": 3.0, "damage": 35.0, "attack_range": 1.5 },
	"mage_zombie": { "hp": 80.0, "speed": 2.5, "charge_speed": 4.0, "damage": 25.0, "attack_range": 1.2 },
	"exploder": { "hp": 35.0, "speed": 4.0, "charge_speed": 6.0, "damage": 30.0, "attack_range": 1.8 },
}

# Ambient growl system
var growl_timer: float = 0.0
var growl_interval: float = 10.0  # Randomized per zombie in _ready
var is_stalker: bool = false  # 30% chance — stalkers circle instead of rushing

func _ready() -> void:
	_apply_zombie_type()
	super._ready()

	# Zombies are slightly more aggressive than gahnomes
	aggression = randf_range(0.6, 0.95)
	patience = randf_range(0.3, 0.6)

	health = max_health

	# Randomize initial growl timing so zombies don't all growl at once
	growl_timer = randf_range(2.0, 8.0)
	growl_interval = randf_range(5.0, 15.0)

	# 30% of zombies become stalkers (circle and ambush instead of direct chase)
	is_stalker = randf() < 0.3
	if is_stalker:
		patience = randf_range(0.6, 0.9)  # More patient
		aggression = randf_range(0.3, 0.6)  # Less aggressive until they commit

## Configure stats and name based on zombie_type
func _apply_zombie_type() -> void:
	var stats = ZOMBIE_STATS.get(zombie_type, ZOMBIE_STATS["walker"])

	enemy_name = "Zombie"
	max_health = stats["hp"]
	move_speed = stats["speed"]
	charge_speed = stats["charge_speed"]
	strafe_speed = stats["speed"] * 0.5
	attack_range = stats["attack_range"]
	weapon_id = "zombie_%s_fists" % zombie_type  # Type-specific weapon for proper damage
	loot_table = { "bone": 2, "rotten_flesh": 1 }

	# Brutes are tankier with slower attacks
	if zombie_type == "brute":
		attack_cooldown_time = 2.0
		windup_time = 0.8
		detection_range = 16.0
		preferred_distance = 4.0
	elif zombie_type == "runner":
		attack_cooldown_time = 0.8
		windup_time = 0.3
		detection_range = 24.0
		preferred_distance = 3.0
	elif zombie_type == "exploder":
		attack_cooldown_time = 1.0
		windup_time = 0.6
		detection_range = 20.0
		preferred_distance = 2.0
	elif zombie_type == "mage_zombie":
		attack_cooldown_time = 1.5
		windup_time = 0.6
		detection_range = 22.0
		preferred_distance = 8.0
		throw_range = 14.0
		throw_min_range = 5.0
		rock_damage = stats["damage"]
	else:
		# Walker - balanced defaults
		attack_cooldown_time = 1.2
		windup_time = 0.5
		detection_range = 18.0
		preferred_distance = 5.0

	# Zombie resistances - undead creature
	damage_resistances = {
		WeaponData.DamageType.SLASH: 0.9,    # Slightly resistant (dead flesh)
		WeaponData.DamageType.BLUNT: 1.1,    # Slightly weak (brittle bones)
		WeaponData.DamageType.PIERCE: 0.8,   # Resistant (holes don't matter to undead)
		WeaponData.DamageType.FIRE: 1.4,     # Weak to fire (dry and burnable)
		WeaponData.DamageType.ICE: 0.9,      # Slightly resistant (already cold)
		WeaponData.DamageType.POISON: 0.5,   # Very resistant (already dead)
	}

## Set zombie type externally (e.g., from spawner before adding to tree)
func set_zombie_type(type: String) -> void:
	zombie_type = type

## Override body setup to use 3D procedural mesh (green-skinned humanoid)
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	body_container.position.y = -0.15  # Lower body to align feet with ground
	add_child(body_container)

	var scale_factor: float = 0.82

	# Scale brutes up and runners slightly smaller
	if zombie_type == "brute":
		scale_factor = 1.1
	elif zombie_type == "runner":
		scale_factor = 0.75

	# Zombie materials - gold/orange danger tones (blue-gold palette)
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.7, 0.5, 0.2, 1)  # Gold-tan skin

	var clothes_mat = StandardMaterial3D.new()
	clothes_mat.albedo_color = Color(0.3, 0.18, 0.05, 1)  # Dark burnt orange clothes

	var bone_mat = StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.9, 0.8, 0.5, 1)  # Pale gold bone color

	# Type-specific color variations
	if zombie_type == "brute":
		skin_mat.albedo_color = Color(0.6, 0.4, 0.15, 1)  # Darker gold
		clothes_mat.albedo_color = Color(0.25, 0.12, 0.03, 1)  # Darker burnt rags
	elif zombie_type == "runner":
		skin_mat.albedo_color = Color(0.8, 0.6, 0.25, 1)  # Lighter gold, agile looking
	elif zombie_type == "mage_zombie":
		skin_mat.albedo_color = Color(0.5, 0.4, 0.55, 1)  # Purple-gold tint
		clothes_mat.albedo_color = Color(0.15, 0.1, 0.3, 1)  # Dark purple robes
	elif zombie_type == "exploder":
		skin_mat.albedo_color = Color(0.8, 0.55, 0.15, 1)  # Bright orange-gold
		# Glowing belly for exploder
		var glow_mat = StandardMaterial3D.new()
		glow_mat.albedo_color = Color(0.8, 0.5, 0.0, 1)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(1.0, 0.6, 0.0, 1)
		glow_mat.emission_energy_multiplier = 1.5

	# Hips
	var hips = MeshInstance3D.new()
	var hips_mesh = BoxMesh.new()
	hips_mesh.size = Vector3(0.2, 0.15, 0.12) * scale_factor
	hips.mesh = hips_mesh
	hips.material_override = clothes_mat
	hips.position = Vector3(0, 0.55 * scale_factor, 0)
	body_container.add_child(hips)

	# Torso
	torso = MeshInstance3D.new()
	var torso_mesh = CapsuleMesh.new()
	torso_mesh.radius = 0.1 * scale_factor
	torso_mesh.height = 0.4 * scale_factor
	torso.mesh = torso_mesh
	torso.material_override = clothes_mat
	torso.position = Vector3(0, 0.75 * scale_factor, 0)
	# Zombies slouch slightly
	torso.rotation.x = 0.15
	body_container.add_child(torso)

	# Neck (thin, exposed)
	var neck = MeshInstance3D.new()
	var neck_mesh = CapsuleMesh.new()
	neck_mesh.radius = 0.025 * scale_factor
	neck_mesh.height = 0.1 * scale_factor
	neck.mesh = neck_mesh
	neck.material_override = skin_mat
	neck.position = Vector3(0, 0.92 * scale_factor, 0.02 * scale_factor)
	body_container.add_child(neck)

	# Head (slightly misshapen)
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.09 * scale_factor
	head_mesh.height = 0.18 * scale_factor
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0, 1.0 * scale_factor, 0.03 * scale_factor)
	# Head tilted slightly
	head.rotation.z = 0.1
	body_container.add_child(head)

	# Sunken eyes (gold glowing)
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.79, 0.0, 1)  # Gold eyes
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.7, 0.0, 1)
	eye_mat.emission_energy_multiplier = 0.8
	if zombie_type == "mage_zombie":
		eye_mat.emission = Color(0.6, 0.3, 0.9, 1)  # Purple glowing eyes for mage
		eye_mat.emission_energy_multiplier = 1.5

	var eye_mesh = SphereMesh.new()
	var eye_radius = 0.018 * scale_factor
	eye_mesh.radius = eye_radius
	eye_mesh.height = eye_radius * 2.0

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.035 * scale_factor, 0.02 * scale_factor, 0.07 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.035 * scale_factor, 0.02 * scale_factor, 0.07 * scale_factor)
	head.add_child(right_eye)

	# Jaw (open, hanging)
	var jaw = MeshInstance3D.new()
	var jaw_mesh = BoxMesh.new()
	jaw_mesh.size = Vector3(0.07, 0.03, 0.06) * scale_factor
	jaw.mesh = jaw_mesh
	jaw.material_override = skin_mat
	jaw.position = Vector3(0, -0.06 * scale_factor, 0.05 * scale_factor)
	jaw.rotation.x = 0.2  # Slightly open
	head.add_child(jaw)

	# Legs
	var thigh_mesh = CapsuleMesh.new()
	thigh_mesh.radius = 0.04 * scale_factor
	thigh_mesh.height = 0.2 * scale_factor

	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.07 * scale_factor, 0.55 * scale_factor, 0)
	body_container.add_child(left_leg)

	var left_thigh = MeshInstance3D.new()
	left_thigh.mesh = thigh_mesh
	left_thigh.material_override = clothes_mat
	left_thigh.position = Vector3(0, -0.1 * scale_factor, 0)
	left_leg.add_child(left_thigh)

	var left_knee = Node3D.new()
	left_knee.name = "Knee"
	left_knee.position = Vector3(0, -0.2 * scale_factor, 0)
	left_leg.add_child(left_knee)

	var left_shin = MeshInstance3D.new()
	left_shin.mesh = thigh_mesh
	left_shin.material_override = clothes_mat
	left_shin.position = Vector3(0, -0.1 * scale_factor, 0)
	left_knee.add_child(left_shin)

	right_leg = Node3D.new()
	right_leg.position = Vector3(0.07 * scale_factor, 0.55 * scale_factor, 0)
	body_container.add_child(right_leg)

	var right_thigh = MeshInstance3D.new()
	right_thigh.mesh = thigh_mesh
	right_thigh.material_override = clothes_mat
	right_thigh.position = Vector3(0, -0.1 * scale_factor, 0)
	right_leg.add_child(right_thigh)

	var right_knee = Node3D.new()
	right_knee.name = "Knee"
	right_knee.position = Vector3(0, -0.2 * scale_factor, 0)
	right_leg.add_child(right_knee)

	var right_shin = MeshInstance3D.new()
	right_shin.mesh = thigh_mesh
	right_shin.material_override = clothes_mat
	right_shin.position = Vector3(0, -0.1 * scale_factor, 0)
	right_knee.add_child(right_shin)

	# Arms (one arm slightly longer, asymmetric zombie look)
	var arm_mesh = CapsuleMesh.new()
	arm_mesh.radius = 0.03 * scale_factor
	arm_mesh.height = 0.18 * scale_factor

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.13 * scale_factor, 0.88 * scale_factor, 0.02 * scale_factor)
	# Left arm hangs forward (zombie slouch)
	left_arm.rotation.x = -0.3
	body_container.add_child(left_arm)

	var left_upper = MeshInstance3D.new()
	left_upper.mesh = arm_mesh
	left_upper.material_override = skin_mat
	left_upper.position = Vector3(0, -0.09 * scale_factor, 0)
	left_arm.add_child(left_upper)

	var left_elbow = Node3D.new()
	left_elbow.name = "Elbow"
	left_elbow.position = Vector3(0, -0.18 * scale_factor, 0)
	left_arm.add_child(left_elbow)

	var left_forearm = MeshInstance3D.new()
	left_forearm.mesh = arm_mesh
	left_forearm.material_override = skin_mat
	left_forearm.position = Vector3(0, -0.09 * scale_factor, 0)
	left_elbow.add_child(left_forearm)

	right_arm = Node3D.new()
	right_arm.position = Vector3(0.13 * scale_factor, 0.88 * scale_factor, 0.02 * scale_factor)
	# Right arm extends forward more (reaching)
	right_arm.rotation.x = -0.5
	body_container.add_child(right_arm)

	var right_upper = MeshInstance3D.new()
	right_upper.mesh = arm_mesh
	right_upper.material_override = skin_mat
	right_upper.position = Vector3(0, -0.09 * scale_factor, 0)
	right_arm.add_child(right_upper)

	var right_elbow = Node3D.new()
	right_elbow.name = "Elbow"
	right_elbow.position = Vector3(0, -0.18 * scale_factor, 0)
	right_arm.add_child(right_elbow)

	var right_forearm = MeshInstance3D.new()
	right_forearm.mesh = arm_mesh
	right_forearm.material_override = skin_mat
	right_forearm.position = Vector3(0, -0.09 * scale_factor, 0)
	right_elbow.add_child(right_forearm)

	# Exposed bone on one arm (detail)
	var bone_spot = MeshInstance3D.new()
	var bone_mesh = CapsuleMesh.new()
	bone_mesh.radius = 0.012 * scale_factor
	bone_mesh.height = 0.06 * scale_factor
	bone_spot.mesh = bone_mesh
	bone_spot.material_override = bone_mat
	bone_spot.position = Vector3(0.01 * scale_factor, -0.05 * scale_factor, 0.02 * scale_factor)
	left_upper.add_child(bone_spot)

	head_base_height = 1.0 * scale_factor

func _get_death_sound() -> String:
	return "enemy_death"

## Override telegraph to use red-ish warning tint for zombies
func _set_windup_telegraph(enabled: bool) -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	if enabled:
		# Swing arm BACK to telegraph attack
		if right_arm:
			original_arm_rotation = right_arm.rotation.x
			windup_tween = create_tween()
			windup_tween.tween_property(right_arm, "rotation:x", 1.0, 0.25)
		# Red-ish warning tint for zombies
		_set_body_tint(Color(1.0, 0.4, 0.4, 1.0))
	else:
		if right_arm:
			right_arm.rotation.x = -0.5  # Return to zombie slouch pose
		_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

## Override attack swing animation
func _play_attack_swing() -> void:
	if not right_arm:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	windup_tween = create_tween()
	# Fast swing forward (zombie lunge)
	windup_tween.tween_property(right_arm, "rotation:x", -1.2, 0.1)
	windup_tween.tween_property(right_arm, "rotation:x", -0.5, 0.3)  # Back to slouch

	_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

# ============================================================================
# AMBIENT GROWL & STALKING BEHAVIOR
# ============================================================================

## Update growl timer — plays growl sounds at zombie's position for 3D audio
func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if is_dead or not is_host:
		return

	# Ambient growl timer
	growl_timer -= delta
	if growl_timer <= 0:
		_play_growl()
		# Growl more frequently while stalking or chasing
		if ai_state == AIState.STALKING:
			growl_timer = randf_range(3.0, 8.0)
		elif ai_state == AIState.CHARGING or ai_state == AIState.CIRCLING:
			growl_timer = randf_range(2.0, 5.0)
		else:
			growl_timer = randf_range(5.0, 15.0)

func _play_growl() -> void:
	"""Play a zombie growl attached to this zombie — 3D audio follows as it moves."""
	# Slight pitch variation for variety
	var pitch = randf_range(0.8, 1.2)
	var volume = -12.0  # Quiet enough to be ambient but audible at distance
	if ai_state == AIState.STALKING:
		volume = -8.0  # Slightly louder when stalking (building tension)
	SoundManager.play_sound_attached("zombie_growl", self, volume, pitch)

## Override stalking behavior for stalker-type zombies
func _update_stalking(delta: float, distance: float) -> void:
	if not is_stalker:
		# Normal zombies use default stalking from enemy.gd
		super._update_stalking(delta, distance)
		return

	# STALKER BEHAVIOR: Circle at distance, wait for opportunity
	_face_target()

	# Check for pack attack: count nearby zombies
	var nearby_zombies := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy != self and enemy is Enemy and is_instance_valid(enemy):
			if enemy.global_position.distance_to(global_position) < 15.0:
				nearby_zombies += 1

	# Check if player is facing away from us
	var player_facing_away := false
	if target_player and is_instance_valid(target_player):
		var to_zombie = (global_position - target_player.global_position).normalized()
		var player_forward = -target_player.global_transform.basis.z
		player_forward.y = 0
		player_forward = player_forward.normalized()
		to_zombie.y = 0
		# If dot product is negative, player is facing away from zombie
		player_facing_away = to_zombie.dot(player_forward) < -0.2

	# Rush conditions: player facing away, or pack attack (2+ nearby zombies), or very close
	if distance < 10.0 or player_facing_away or nearby_zombies >= 2:
		_change_state(AIState.CHARGING)
		charge_target_pos = target_player.global_position
		return

	# Stay at 12-18 unit distance and circle around player
	var ideal_distance = randf_range(12.0, 18.0)
	var to_player = target_player.global_position - global_position
	to_player.y = 0
	to_player = to_player.normalized()

	# Perpendicular direction for circling (offset from player's facing direction)
	var strafe_dir = Vector3(-to_player.z, 0, to_player.x) * circle_direction

	# Adjust distance: approach if too far, retreat if too close
	var distance_diff = distance - ideal_distance
	var approach_factor = clamp(distance_diff / 5.0, -0.5, 0.5)
	var move_dir = (strafe_dir * 0.7 + to_player * approach_factor).normalized()

	velocity.x = move_dir.x * strafe_speed * 0.6  # Move slowly while stalking
	velocity.z = move_dir.z * strafe_speed * 0.6

	# Occasionally change circle direction
	if state_timer > 3.0 + randf() * 2.0:
		circle_direction *= -1
		state_timer = 0.0

	# After a long stalk, commit to attack regardless
	if state_timer > 8.0 + patience * 4.0:
		_change_state(AIState.CHARGING)
		charge_target_pos = target_player.global_position
