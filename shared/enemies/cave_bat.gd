extends "res://shared/enemies/enemy.gd"

## Cave Bat - Fast, fragile flying enemy found in the crystal cave biome
## Swoops in quickly with rapid attacks, flies slightly above ground
## Weak to fire, resistant to dark

func _ready() -> void:
	# Override stats for Cave Bat
	enemy_name = "Cave Bat"
	max_health = 25.0
	move_speed = 8.0  # Very fast
	charge_speed = 10.0  # Lightning fast charge
	strafe_speed = 5.0
	attack_range = 1.0  # Short reach
	attack_cooldown_time = 0.5  # Very fast attacks
	windup_time = 0.2  # Quick telegraph
	detection_range = 24.0  # Good hearing in the dark
	preferred_distance = 6.0
	throw_range = 0.0  # No rock throwing
	throw_min_range = 0.0
	loot_table = {"bone": 1}
	rare_loot_table = {"ectoplasm": [1, 0.15]}  # 15% chance
	weapon_id = "cave_bat_fangs"

	# Cave Bat resistances - dark-dwelling flying creature
	damage_resistances = {
		WeaponData.DamageType.SLASH: 1.0,    # Neutral
		WeaponData.DamageType.BLUNT: 1.0,    # Neutral
		WeaponData.DamageType.PIERCE: 1.0,   # Neutral
		WeaponData.DamageType.FIRE: 1.5,     # 50% WEAK to fire (burns easily)
		WeaponData.DamageType.ICE: 1.0,      # Neutral
		WeaponData.DamageType.POISON: 1.0,   # Neutral
		WeaponData.DamageType.DARK: 0.5,     # 50% resistant to dark (cave dweller)
	}

	# Call parent ready
	super._ready()

	# High aggression, low patience - swoops in fast
	aggression = randf_range(0.7, 0.95)
	patience = randf_range(0.1, 0.3)

	health = max_health

## Override body setup for small dark bat with wing-like triangles
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	body_container.position.y = 0.6  # Float above ground (flying)
	add_child(body_container)

	var scale_factor: float = 0.55  # Small creature

	# Bat materials - dark blue-black
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.05, 0.05, 0.15, 1)  # Very dark blue-black

	var wing_mat = StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.08, 0.08, 0.2, 1)  # Slightly lighter blue-black
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Wings visible from both sides

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.0, 0.08, 1.0, 1)  # Blue eyes (#0014ff)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.0, 0.08, 1.0, 1)
	eye_mat.emission_energy_multiplier = 2.0

	var fang_mat = StandardMaterial3D.new()
	fang_mat.albedo_color = Color(0.9, 0.9, 0.95, 1)  # White fangs

	# Body - small oval
	torso = MeshInstance3D.new()
	var torso_mesh = SphereMesh.new()
	torso_mesh.radius = 0.1 * scale_factor
	torso_mesh.height = 0.16 * scale_factor
	torso.mesh = torso_mesh
	torso.material_override = body_mat
	torso.position = Vector3(0, 0.5 * scale_factor, 0)
	body_container.add_child(torso)

	# Head - slightly larger sphere
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.08 * scale_factor
	head_mesh.height = 0.14 * scale_factor
	head.mesh = head_mesh
	head.material_override = body_mat
	head.position = Vector3(0, 0.65 * scale_factor, 0.04 * scale_factor)
	body_container.add_child(head)

	# Ears (tall pointed triangular prisms)
	var ear_mesh = CylinderMesh.new()
	ear_mesh.top_radius = 0.0  # Pointed top
	ear_mesh.bottom_radius = 0.025 * scale_factor
	ear_mesh.height = 0.08 * scale_factor

	var left_ear = MeshInstance3D.new()
	left_ear.mesh = ear_mesh
	left_ear.material_override = body_mat
	left_ear.position = Vector3(-0.04 * scale_factor, 0.08 * scale_factor, 0)
	left_ear.rotation.z = -0.3
	head.add_child(left_ear)

	var right_ear = MeshInstance3D.new()
	right_ear.mesh = ear_mesh
	right_ear.material_override = body_mat
	right_ear.position = Vector3(0.04 * scale_factor, 0.08 * scale_factor, 0)
	right_ear.rotation.z = 0.3
	head.add_child(right_ear)

	# Glowing eyes
	var eye_mesh_res = SphereMesh.new()
	var eye_radius = 0.015 * scale_factor
	eye_mesh_res.radius = eye_radius
	eye_mesh_res.height = eye_radius * 2.0

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh_res
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.03 * scale_factor, 0.02 * scale_factor, 0.06 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh_res
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.03 * scale_factor, 0.02 * scale_factor, 0.06 * scale_factor)
	head.add_child(right_eye)

	# Fangs (small white cones)
	var fang_mesh = CylinderMesh.new()
	fang_mesh.top_radius = 0.005 * scale_factor
	fang_mesh.bottom_radius = 0.0
	fang_mesh.height = 0.03 * scale_factor

	var left_fang = MeshInstance3D.new()
	left_fang.mesh = fang_mesh
	left_fang.material_override = fang_mat
	left_fang.position = Vector3(-0.015 * scale_factor, -0.04 * scale_factor, 0.05 * scale_factor)
	head.add_child(left_fang)

	var right_fang = MeshInstance3D.new()
	right_fang.mesh = fang_mesh
	right_fang.material_override = fang_mat
	right_fang.position = Vector3(0.015 * scale_factor, -0.04 * scale_factor, 0.05 * scale_factor)
	head.add_child(right_fang)

	# Wings - flat triangular shapes using PrismMesh for triangle look
	# Left wing
	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.08 * scale_factor, 0.52 * scale_factor, 0)
	body_container.add_child(left_arm)

	var left_wing = MeshInstance3D.new()
	var left_wing_mesh = PrismMesh.new()
	left_wing_mesh.size = Vector3(0.3 * scale_factor, 0.01 * scale_factor, 0.15 * scale_factor)
	left_wing.mesh = left_wing_mesh
	left_wing.material_override = wing_mat
	left_wing.position = Vector3(-0.12 * scale_factor, 0, 0)
	left_wing.rotation.z = 0.2  # Slight upward angle
	left_arm.add_child(left_wing)

	# Right wing
	right_arm = Node3D.new()
	right_arm.position = Vector3(0.08 * scale_factor, 0.52 * scale_factor, 0)
	body_container.add_child(right_arm)

	var right_wing = MeshInstance3D.new()
	var right_wing_mesh = PrismMesh.new()
	right_wing_mesh.size = Vector3(0.3 * scale_factor, 0.01 * scale_factor, 0.15 * scale_factor)
	right_wing.mesh = right_wing_mesh
	right_wing.material_override = wing_mat
	right_wing.position = Vector3(0.12 * scale_factor, 0, 0)
	right_wing.rotation.z = -0.2
	right_arm.add_child(right_wing)

	# Small feet (vestigial, tucked under body)
	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.03 * scale_factor, 0.42 * scale_factor, 0)
	body_container.add_child(left_leg)

	var left_foot = MeshInstance3D.new()
	var foot_mesh = CylinderMesh.new()
	foot_mesh.top_radius = 0.01 * scale_factor
	foot_mesh.bottom_radius = 0.005 * scale_factor
	foot_mesh.height = 0.04 * scale_factor
	left_foot.mesh = foot_mesh
	left_foot.material_override = body_mat
	left_foot.position = Vector3(0, -0.02 * scale_factor, 0)
	left_leg.add_child(left_foot)

	right_leg = Node3D.new()
	right_leg.position = Vector3(0.03 * scale_factor, 0.42 * scale_factor, 0)
	body_container.add_child(right_leg)

	var right_foot = MeshInstance3D.new()
	right_foot.mesh = foot_mesh
	right_foot.material_override = body_mat
	right_foot.position = Vector3(0, -0.02 * scale_factor, 0)
	right_leg.add_child(right_foot)

	head_base_height = 0.65 * scale_factor

# Wing flap animation timer
var wing_flap_time: float = 0.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	if is_dead:
		return

	# Continuous wing flap animation
	wing_flap_time += delta * 12.0  # Fast flapping
	if left_arm:
		left_arm.rotation.z = sin(wing_flap_time) * 0.4 + 0.1
	if right_arm:
		right_arm.rotation.z = -sin(wing_flap_time) * 0.4 - 0.1

func _get_death_sound() -> String:
	return "enemy_death"

## Override telegraph - quick flash before bite
func _set_windup_telegraph(enabled: bool) -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	if enabled:
		# Lunge body forward
		if torso:
			windup_tween = create_tween()
			windup_tween.tween_property(body_container, "position:z", 0.05, 0.1)
		# Blue warning tint
		_set_body_tint(Color(0.4, 0.4, 1.0, 1.0))
	else:
		if body_container:
			body_container.position.z = 0.0
		_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))

## Override attack swing - quick snap bite
func _play_attack_swing() -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	windup_tween = create_tween()
	# Quick lunge forward then back
	windup_tween.tween_property(body_container, "position:z", 0.15, 0.08)
	windup_tween.tween_property(body_container, "position:z", 0.0, 0.15)

	_set_body_tint(Color(1.0, 1.0, 1.0, 1.0))
