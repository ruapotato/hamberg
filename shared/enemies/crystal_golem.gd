extends "res://shared/enemies/enemy.gd"

## Crystal Golem - Tanky cave enemy found in the crystal cave biome
## Slow but hits hard, built from crystallized rock
## Resistant to pierce and ice, weak to blunt and fire

func _ready() -> void:
	# Override stats for Crystal Golem
	enemy_name = "Crystal Golem"
	max_health = 200.0
	move_speed = 2.0  # Slow, lumbering
	charge_speed = 3.0  # Slow charge
	strafe_speed = 1.0
	attack_range = 1.5  # Long reach (large creature)
	attack_cooldown_time = 2.0  # Slow attacks
	windup_time = 0.8  # Long telegraph
	detection_range = 16.0
	preferred_distance = 5.0
	throw_range = 0.0  # No rock throwing
	throw_min_range = 0.0
	loot_table = {"stone": 3}
	rare_loot_table = {"crystal_shard": [2, 0.30]}  # 30% chance
	weapon_id = "crystal_golem_fists"

	# Crystal Golem resistances - living crystal/rock
	# Very resistant to pierce (solid crystal), weak to blunt (shatter) and fire (thermal shock)
	damage_resistances = {
		WeaponData.DamageType.SLASH: 0.7,    # 30% resistant (hard crystal surface)
		WeaponData.DamageType.BLUNT: 1.5,    # 50% WEAK to blunt (shatters crystal)
		WeaponData.DamageType.PIERCE: 0.4,   # 60% resistant (very hard to pierce)
		WeaponData.DamageType.FIRE: 1.3,     # 30% weak to fire (thermal shock)
		WeaponData.DamageType.ICE: 0.5,      # 50% resistant (already cold crystal)
		WeaponData.DamageType.POISON: 1.0,   # Neutral (inorganic)
	}

	# Call parent ready
	super._ready()

	# Low aggression but not very patient - charges when ready
	aggression = randf_range(0.4, 0.7)
	patience = randf_range(0.3, 0.5)

	health = max_health

## Override body setup for angular crystalline golem appearance
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	var scale_factor: float = 1.15  # Large, imposing

	# Crystal materials - PINK crystal (#ff0093)
	var crystal_mat = StandardMaterial3D.new()
	crystal_mat.albedo_color = Color(1.0, 0.0, 0.576, 1)  # #ff0093 pink
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Color(1.0, 0.0, 0.576, 1)
	crystal_mat.emission_energy_multiplier = 0.4

	var rock_mat = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.3, 0.25, 0.35, 1)  # Dark purple-gray rock

	var dark_crystal_mat = StandardMaterial3D.new()
	dark_crystal_mat.albedo_color = Color(0.6, 0.0, 0.35, 1)  # Darker pink crystal
	dark_crystal_mat.emission_enabled = true
	dark_crystal_mat.emission = Color(0.8, 0.0, 0.45, 1)
	dark_crystal_mat.emission_energy_multiplier = 0.3

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.0, 0.576, 1)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.0, 0.576, 1)  # Bright pink glowing eyes
	eye_mat.emission_energy_multiplier = 2.5

	# Hips - wide rocky base
	var hips = MeshInstance3D.new()
	var hips_mesh = BoxMesh.new()
	hips_mesh.size = Vector3(0.3, 0.18, 0.2) * scale_factor
	hips.mesh = hips_mesh
	hips.material_override = rock_mat
	hips.position = Vector3(0, 0.5 * scale_factor, 0)
	body_container.add_child(hips)

	# Torso - large blocky chest
	torso = MeshInstance3D.new()
	var torso_mesh = BoxMesh.new()
	torso_mesh.size = Vector3(0.35, 0.35, 0.25) * scale_factor
	torso.mesh = torso_mesh
	torso.material_override = rock_mat
	torso.position = Vector3(0, 0.75 * scale_factor, 0)
	body_container.add_child(torso)

	# Crystal growths on torso (decorative pink crystals jutting out)
	var crystal_mesh = BoxMesh.new()
	crystal_mesh.size = Vector3(0.06, 0.14, 0.06) * scale_factor

	var crystal_positions = [
		Vector3(0.12, 0.12, 0.08) * scale_factor,
		Vector3(-0.1, 0.15, 0.1) * scale_factor,
		Vector3(0.08, 0.1, -0.1) * scale_factor,
		Vector3(-0.14, 0.08, -0.05) * scale_factor,
	]
	var crystal_rotations = [0.3, -0.4, 0.2, -0.25]

	for i in crystal_positions.size():
		var crystal = MeshInstance3D.new()
		crystal.mesh = crystal_mesh
		crystal.material_override = crystal_mat
		crystal.position = crystal_positions[i]
		crystal.rotation.z = crystal_rotations[i]
		crystal.rotation.x = crystal_rotations[i] * 0.5
		torso.add_child(crystal)

	# Shoulder crystals (larger, more prominent)
	var shoulder_crystal_mesh = BoxMesh.new()
	shoulder_crystal_mesh.size = Vector3(0.08, 0.18, 0.08) * scale_factor

	var left_shoulder_crystal = MeshInstance3D.new()
	left_shoulder_crystal.mesh = shoulder_crystal_mesh
	left_shoulder_crystal.material_override = crystal_mat
	left_shoulder_crystal.position = Vector3(-0.18 * scale_factor, 0.15 * scale_factor, 0)
	left_shoulder_crystal.rotation.z = 0.5
	torso.add_child(left_shoulder_crystal)

	var right_shoulder_crystal = MeshInstance3D.new()
	right_shoulder_crystal.mesh = shoulder_crystal_mesh
	right_shoulder_crystal.material_override = crystal_mat
	right_shoulder_crystal.position = Vector3(0.18 * scale_factor, 0.15 * scale_factor, 0)
	right_shoulder_crystal.rotation.z = -0.5
	torso.add_child(right_shoulder_crystal)

	# Head - angular box shape
	head = MeshInstance3D.new()
	var head_mesh = BoxMesh.new()
	head_mesh.size = Vector3(0.16, 0.14, 0.14) * scale_factor
	head.mesh = head_mesh
	head.material_override = dark_crystal_mat
	head.position = Vector3(0, 0.98 * scale_factor, 0)
	body_container.add_child(head)

	# Head crystal spike (top of head)
	var head_spike = MeshInstance3D.new()
	var spike_mesh = BoxMesh.new()
	spike_mesh.size = Vector3(0.04, 0.1, 0.04) * scale_factor
	head_spike.mesh = spike_mesh
	head_spike.material_override = crystal_mat
	head_spike.position = Vector3(0, 0.1 * scale_factor, 0)
	head_spike.rotation.z = 0.15
	head.add_child(head_spike)

	# Glowing eyes
	var eye_mesh = SphereMesh.new()
	var eye_radius = 0.02 * scale_factor
	eye_mesh.radius = eye_radius
	eye_mesh.height = eye_radius * 2.0

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.04 * scale_factor, 0.01 * scale_factor, 0.07 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.04 * scale_factor, 0.01 * scale_factor, 0.07 * scale_factor)
	head.add_child(right_eye)

	# Legs - thick rocky pillars
	var thigh_mesh = BoxMesh.new()
	thigh_mesh.size = Vector3(0.1, 0.2, 0.1) * scale_factor

	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.1 * scale_factor, 0.5 * scale_factor, 0)
	body_container.add_child(left_leg)

	var left_thigh = MeshInstance3D.new()
	left_thigh.mesh = thigh_mesh
	left_thigh.material_override = rock_mat
	left_thigh.position = Vector3(0, -0.1 * scale_factor, 0)
	left_leg.add_child(left_thigh)

	var left_knee = Node3D.new()
	left_knee.name = "Knee"
	left_knee.position = Vector3(0, -0.2 * scale_factor, 0)
	left_leg.add_child(left_knee)

	var left_shin = MeshInstance3D.new()
	left_shin.mesh = thigh_mesh
	left_shin.material_override = rock_mat
	left_shin.position = Vector3(0, -0.1 * scale_factor, 0)
	left_knee.add_child(left_shin)

	right_leg = Node3D.new()
	right_leg.position = Vector3(0.1 * scale_factor, 0.5 * scale_factor, 0)
	body_container.add_child(right_leg)

	var right_thigh = MeshInstance3D.new()
	right_thigh.mesh = thigh_mesh
	right_thigh.material_override = rock_mat
	right_thigh.position = Vector3(0, -0.1 * scale_factor, 0)
	right_leg.add_child(right_thigh)

	var right_knee = Node3D.new()
	right_knee.name = "Knee"
	right_knee.position = Vector3(0, -0.2 * scale_factor, 0)
	right_leg.add_child(right_knee)

	var right_shin = MeshInstance3D.new()
	right_shin.mesh = thigh_mesh
	right_shin.material_override = rock_mat
	right_shin.position = Vector3(0, -0.1 * scale_factor, 0)
	right_knee.add_child(right_shin)

	# Arms - thick rocky limbs with crystal fists
	var arm_mesh = BoxMesh.new()
	arm_mesh.size = Vector3(0.08, 0.18, 0.08) * scale_factor

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.2 * scale_factor, 0.88 * scale_factor, 0)
	body_container.add_child(left_arm)

	var left_upper = MeshInstance3D.new()
	left_upper.mesh = arm_mesh
	left_upper.material_override = rock_mat
	left_upper.position = Vector3(0, -0.09 * scale_factor, 0)
	left_arm.add_child(left_upper)

	var left_elbow = Node3D.new()
	left_elbow.name = "Elbow"
	left_elbow.position = Vector3(0, -0.18 * scale_factor, 0)
	left_arm.add_child(left_elbow)

	var left_forearm = MeshInstance3D.new()
	left_forearm.mesh = arm_mesh
	left_forearm.material_override = dark_crystal_mat
	left_forearm.position = Vector3(0, -0.09 * scale_factor, 0)
	left_elbow.add_child(left_forearm)

	# Crystal fist (left)
	var fist_mesh = BoxMesh.new()
	fist_mesh.size = Vector3(0.1, 0.1, 0.1) * scale_factor
	var left_fist = MeshInstance3D.new()
	left_fist.mesh = fist_mesh
	left_fist.material_override = crystal_mat
	left_fist.position = Vector3(0, -0.12 * scale_factor, 0)
	left_elbow.add_child(left_fist)

	right_arm = Node3D.new()
	right_arm.position = Vector3(0.2 * scale_factor, 0.88 * scale_factor, 0)
	body_container.add_child(right_arm)

	var right_upper = MeshInstance3D.new()
	right_upper.mesh = arm_mesh
	right_upper.material_override = rock_mat
	right_upper.position = Vector3(0, -0.09 * scale_factor, 0)
	right_arm.add_child(right_upper)

	var right_elbow = Node3D.new()
	right_elbow.name = "Elbow"
	right_elbow.position = Vector3(0, -0.18 * scale_factor, 0)
	right_arm.add_child(right_elbow)

	var right_forearm = MeshInstance3D.new()
	right_forearm.mesh = arm_mesh
	right_forearm.material_override = dark_crystal_mat
	right_forearm.position = Vector3(0, -0.09 * scale_factor, 0)
	right_elbow.add_child(right_forearm)

	# Crystal fist (right)
	var right_fist = MeshInstance3D.new()
	right_fist.mesh = fist_mesh
	right_fist.material_override = crystal_mat
	right_fist.position = Vector3(0, -0.12 * scale_factor, 0)
	right_elbow.add_child(right_fist)

	head_base_height = 0.98 * scale_factor

func _get_death_sound() -> String:
	return "enemy_death"

## Override telegraph to use crystal-pink warning tint
func _set_windup_telegraph(enabled: bool) -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	if enabled:
		# Raise arm back to telegraph heavy slam
		if right_arm:
			original_arm_rotation = right_arm.rotation.x
			windup_tween = create_tween()
			windup_tween.tween_property(right_arm, "rotation:x", 1.2, 0.4)
		# Pink crystal warning glow
		_set_body_tint(Color(1.0, 0.3, 0.6, 1.0))
	else:
		if right_arm:
			right_arm.rotation.x = 0.0
		_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

## Override attack swing animation - heavy slam
func _play_attack_swing() -> void:
	if not right_arm:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	windup_tween = create_tween()
	# Heavy slam downward
	windup_tween.tween_property(right_arm, "rotation:x", -1.5, 0.12)
	windup_tween.tween_property(right_arm, "rotation:x", 0.0, 0.4)

	_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))
