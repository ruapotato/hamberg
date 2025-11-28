extends "res://shared/enemies/enemy.gd"

## Sporeling - Bioluminescent fungal creature of the dark forest
## Larger, more patient, uses spore cloud attacks
## Different AI: stalks longer, has area-of-effect damage

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
	weapon_id = "fists"

	# Call parent ready
	super._ready()

	# Higher aggression but more patient
	aggression = randf_range(0.5, 0.9)
	patience = randf_range(0.6, 0.9)  # Much more patient

	health = max_health

## Override body setup for bioluminescent fungal appearance
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	var scale_factor: float = 1.2  # 50% larger than Gahnome's 0.79

	# Bioluminescent materials
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.15, 0.2, 0.25, 1)  # Dark blue-gray body
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.0, 0.3, 0.5, 1)  # Cyan glow
	body_mat.emission_energy_multiplier = 0.6

	var cap_mat = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.1, 0.15, 0.3, 1)  # Deep purple-blue cap
	cap_mat.emission_enabled = true
	cap_mat.emission = Color(0.2, 0.1, 0.6, 1)  # Purple glow
	cap_mat.emission_energy_multiplier = 1.2

	var tendril_mat = StandardMaterial3D.new()
	tendril_mat.albedo_color = Color(0.12, 0.18, 0.22, 1)
	tendril_mat.emission_enabled = true
	tendril_mat.emission = Color(0.0, 0.4, 0.35, 1)  # Teal glow
	tendril_mat.emission_energy_multiplier = 0.8

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.0, 0.0, 0.0, 1)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.8, 0.2, 0.8, 1)  # Magenta glowing eyes
	eye_mat.emission_energy_multiplier = 2.0

	# Bulbous body/torso
	torso = MeshInstance3D.new()
	var torso_mesh = SphereMesh.new()
	torso_mesh.radius = 0.18 * scale_factor
	torso_mesh.height = 0.32 * scale_factor
	torso.mesh = torso_mesh
	torso.material_override = body_mat
	torso.position = Vector3(0, 0.5 * scale_factor, 0)
	body_container.add_child(torso)

	# Upper body bulge
	var upper_body = MeshInstance3D.new()
	var upper_mesh = SphereMesh.new()
	upper_mesh.radius = 0.15 * scale_factor
	upper_mesh.height = 0.25 * scale_factor
	upper_body.mesh = upper_mesh
	upper_body.material_override = body_mat
	upper_body.position = Vector3(0, 0.72 * scale_factor, 0)
	body_container.add_child(upper_body)

	# Mushroom cap head
	head = MeshInstance3D.new()
	var head_mesh = CylinderMesh.new()
	head_mesh.top_radius = 0.08 * scale_factor
	head_mesh.bottom_radius = 0.28 * scale_factor
	head_mesh.height = 0.12 * scale_factor
	head.mesh = head_mesh
	head.material_override = cap_mat
	head.position = Vector3(0, 0.92 * scale_factor, 0)
	body_container.add_child(head)

	# Cap dome on top
	var cap_dome = MeshInstance3D.new()
	var dome_mesh = SphereMesh.new()
	dome_mesh.radius = 0.12 * scale_factor
	dome_mesh.height = 0.15 * scale_factor
	cap_dome.mesh = dome_mesh
	cap_dome.material_override = cap_mat
	cap_dome.position = Vector3(0, 0.06 * scale_factor, 0)
	head.add_child(cap_dome)

	# Glowing eyes (multiple, scattered under cap)
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.025 * scale_factor
	eye_mesh.height = 0.05 * scale_factor

	var eye_positions = [
		Vector3(-0.08, -0.02, 0.12) * scale_factor,
		Vector3(0.08, -0.02, 0.12) * scale_factor,
		Vector3(-0.12, -0.03, 0.08) * scale_factor,
		Vector3(0.12, -0.03, 0.08) * scale_factor,
	]

	for pos in eye_positions:
		var eye = MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = pos
		head.add_child(eye)

	# Tendril legs (3 pairs for alien look)
	var leg_positions = [
		Vector3(-0.12, 0.35, 0.05) * scale_factor,
		Vector3(0.12, 0.35, 0.05) * scale_factor,
		Vector3(-0.14, 0.35, -0.03) * scale_factor,
		Vector3(0.14, 0.35, -0.03) * scale_factor,
	]

	var tendril_mesh = CapsuleMesh.new()
	tendril_mesh.radius = 0.035 * scale_factor
	tendril_mesh.height = 0.35 * scale_factor

	# Create leg containers for animation
	left_leg = Node3D.new()
	left_leg.position = leg_positions[0]
	body_container.add_child(left_leg)

	var left_tendril = MeshInstance3D.new()
	left_tendril.mesh = tendril_mesh
	left_tendril.material_override = tendril_mat
	left_tendril.position = Vector3(0, -0.175 * scale_factor, 0)
	left_leg.add_child(left_tendril)

	right_leg = Node3D.new()
	right_leg.position = leg_positions[1]
	body_container.add_child(right_leg)

	var right_tendril = MeshInstance3D.new()
	right_tendril.mesh = tendril_mesh
	right_tendril.material_override = tendril_mat
	right_tendril.position = Vector3(0, -0.175 * scale_factor, 0)
	right_leg.add_child(right_tendril)

	# Back tendrils (non-animated)
	for i in range(2, 4):
		var back_leg = MeshInstance3D.new()
		back_leg.mesh = tendril_mesh
		back_leg.material_override = tendril_mat
		back_leg.position = leg_positions[i] + Vector3(0, -0.175 * scale_factor, 0)
		body_container.add_child(back_leg)

	# Tendril arms (longer, whip-like)
	var arm_mesh = CapsuleMesh.new()
	arm_mesh.radius = 0.025 * scale_factor
	arm_mesh.height = 0.25 * scale_factor

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.16 * scale_factor, 0.65 * scale_factor, 0)
	body_container.add_child(left_arm)

	var left_upper = MeshInstance3D.new()
	left_upper.mesh = arm_mesh
	left_upper.material_override = tendril_mat
	left_upper.position = Vector3(0, -0.125 * scale_factor, 0)
	left_upper.rotation.z = 0.3  # Slight outward angle
	left_arm.add_child(left_upper)

	right_arm = Node3D.new()
	right_arm.position = Vector3(0.16 * scale_factor, 0.65 * scale_factor, 0)
	body_container.add_child(right_arm)

	var right_upper = MeshInstance3D.new()
	right_upper.mesh = arm_mesh
	right_upper.material_override = tendril_mat
	right_upper.position = Vector3(0, -0.125 * scale_factor, 0)
	right_upper.rotation.z = -0.3
	right_arm.add_child(right_upper)

	# Glowing spore spots on body
	var spore_mat = StandardMaterial3D.new()
	spore_mat.albedo_color = Color(0.1, 0.3, 0.2, 1)
	spore_mat.emission_enabled = true
	spore_mat.emission = Color(0.0, 0.8, 0.4, 1)  # Bright green glow
	spore_mat.emission_energy_multiplier = 1.5

	var spot_mesh = SphereMesh.new()
	spot_mesh.radius = 0.02 * scale_factor
	spot_mesh.height = 0.04 * scale_factor

	var spot_positions = [
		Vector3(0.1, 0.55, 0.12) * scale_factor,
		Vector3(-0.12, 0.48, 0.1) * scale_factor,
		Vector3(0.08, 0.62, -0.1) * scale_factor,
		Vector3(-0.06, 0.7, 0.08) * scale_factor,
		Vector3(0.14, 0.5, -0.05) * scale_factor,
	]

	for pos in spot_positions:
		var spot = MeshInstance3D.new()
		spot.mesh = spot_mesh
		spot.material_override = spore_mat
		spot.position = pos
		body_container.add_child(spot)

	head_base_height = 0.92 * scale_factor

## Override telegraph to use spore-specific visual
func _set_windup_telegraph(enabled: bool) -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	if enabled:
		# Pulse glow brighter instead of arm swing
		if right_arm:
			original_arm_rotation = right_arm.rotation.x
			windup_tween = create_tween()
			windup_tween.tween_property(right_arm, "rotation:x", 1.0, 0.35)
		# Tint with spore-green warning
		_set_body_tint(Color(0.4, 1.0, 0.4, 1.0))
	else:
		if right_arm:
			right_arm.rotation.x = 0.0
		_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

## Override attack swing animation
func _play_attack_swing() -> void:
	if not right_arm:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	windup_tween = create_tween()
	windup_tween.tween_property(right_arm, "rotation:x", -0.8, 0.15)
	windup_tween.tween_property(right_arm, "rotation:x", 0.0, 0.35)

	_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))
