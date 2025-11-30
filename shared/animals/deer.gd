extends "res://shared/animals/passive_animal.gd"

## Deer - Graceful forest creature
## Found in meadow and dark_forest biomes
## Drops raw venison when killed

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with deer-specific values
	enemy_name = "Deer"
	max_health = 25.0
	move_speed = 4.0  # Deer are fast
	strafe_speed = 3.0
	loot_table = {"raw_venison": 2, "deer_leather": 2}

	# Deer are skittish - flee when players get close
	is_skittish = true
	flee_detection_range = 12.0  # Deer are very alert

	print("[Deer] Deer ready (network_id=%d)" % network_id)

## Build deer body - elegant quadruped with antlers
## If BodyContainer exists in TSCN with children, uses that mesh instead
func _setup_body() -> void:
	# Check if BodyContainer already exists in the scene (from TSCN)
	var existing_container = get_node_or_null("BodyContainer")
	if existing_container and existing_container.get_child_count() > 0:
		# Use the mesh from TSCN
		body_container = existing_container
		head_base_height = 0.85 * 0.9  # Default deer height
		print("[Deer] Using custom mesh from TSCN")
		return

	# Create procedural mesh if no custom mesh provided
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI  # Face -Z direction (forward in Godot)
	add_child(body_container)

	var scale_factor: float = 0.9

	# Deer fur material - tan/brown
	var fur_mat = StandardMaterial3D.new()
	fur_mat.albedo_color = Color(0.65, 0.5, 0.35, 1)  # Tan brown

	var belly_mat = StandardMaterial3D.new()
	belly_mat.albedo_color = Color(0.8, 0.7, 0.6, 1)  # Lighter belly

	var antler_mat = StandardMaterial3D.new()
	antler_mat.albedo_color = Color(0.4, 0.3, 0.2, 1)  # Dark brown antlers

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.1, 0.05, 0.0, 1)  # Dark eyes

	# Body (horizontal capsule extending front-to-back)
	torso = MeshInstance3D.new()
	var body_mesh = CapsuleMesh.new()
	body_mesh.radius = 0.15 * scale_factor
	body_mesh.height = 0.55 * scale_factor
	torso.mesh = body_mesh
	torso.material_override = fur_mat
	torso.position = Vector3(0, 0.55 * scale_factor, 0)
	torso.rotation.x = PI / 2  # Horizontal along Z axis (front-to-back)
	body_container.add_child(torso)

	# Neck
	var neck = MeshInstance3D.new()
	var neck_mesh = CapsuleMesh.new()
	neck_mesh.radius = 0.06 * scale_factor
	neck_mesh.height = 0.25 * scale_factor
	neck.mesh = neck_mesh
	neck.material_override = fur_mat
	neck.position = Vector3(0, 0.7 * scale_factor, 0.25 * scale_factor)
	neck.rotation.x = -0.4  # Angled forward
	body_container.add_child(neck)

	# Head
	head = MeshInstance3D.new()
	var head_mesh = CapsuleMesh.new()
	head_mesh.radius = 0.07 * scale_factor
	head_mesh.height = 0.18 * scale_factor
	head.mesh = head_mesh
	head.material_override = fur_mat
	head.position = Vector3(0, 0.85 * scale_factor, 0.35 * scale_factor)
	head.rotation.x = PI / 2  # Horizontal
	body_container.add_child(head)

	# Snout
	var snout = MeshInstance3D.new()
	var snout_mesh = BoxMesh.new()
	snout_mesh.size = Vector3(0.06, 0.05, 0.1) * scale_factor
	snout.mesh = snout_mesh
	snout.material_override = belly_mat
	snout.position = Vector3(0, -0.02 * scale_factor, 0.12 * scale_factor)
	head.add_child(snout)

	# Eyes
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.015 * scale_factor
	eye_mesh.height = 0.03 * scale_factor

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.05 * scale_factor, 0.02 * scale_factor, 0.05 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.05 * scale_factor, 0.02 * scale_factor, 0.05 * scale_factor)
	head.add_child(right_eye)

	# Antlers (simple branching)
	var antler_mesh = CylinderMesh.new()
	antler_mesh.top_radius = 0.008 * scale_factor
	antler_mesh.bottom_radius = 0.015 * scale_factor
	antler_mesh.height = 0.2 * scale_factor

	# Left antler
	var left_antler = MeshInstance3D.new()
	left_antler.mesh = antler_mesh
	left_antler.material_override = antler_mat
	left_antler.position = Vector3(-0.04 * scale_factor, 0.12 * scale_factor, 0)
	left_antler.rotation.z = 0.3
	head.add_child(left_antler)

	# Right antler
	var right_antler = MeshInstance3D.new()
	right_antler.mesh = antler_mesh
	right_antler.material_override = antler_mat
	right_antler.position = Vector3(0.04 * scale_factor, 0.12 * scale_factor, 0)
	right_antler.rotation.z = -0.3
	head.add_child(right_antler)

	# Legs (4 legs - front and back pairs)
	var leg_mesh = CapsuleMesh.new()
	leg_mesh.radius = 0.03 * scale_factor
	leg_mesh.height = 0.35 * scale_factor

	# Front left leg
	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.1 * scale_factor, 0.35 * scale_factor, 0.2 * scale_factor)
	body_container.add_child(left_leg)

	var fl_leg_mesh = MeshInstance3D.new()
	fl_leg_mesh.mesh = leg_mesh
	fl_leg_mesh.material_override = fur_mat
	fl_leg_mesh.position = Vector3(0, -0.175 * scale_factor, 0)
	left_leg.add_child(fl_leg_mesh)

	# Front right leg
	right_leg = Node3D.new()
	right_leg.position = Vector3(0.1 * scale_factor, 0.35 * scale_factor, 0.2 * scale_factor)
	body_container.add_child(right_leg)

	var fr_leg_mesh = MeshInstance3D.new()
	fr_leg_mesh.mesh = leg_mesh
	fr_leg_mesh.material_override = fur_mat
	fr_leg_mesh.position = Vector3(0, -0.175 * scale_factor, 0)
	right_leg.add_child(fr_leg_mesh)

	# Back left leg
	var bl_leg = Node3D.new()
	bl_leg.position = Vector3(-0.1 * scale_factor, 0.35 * scale_factor, -0.2 * scale_factor)
	body_container.add_child(bl_leg)

	var bl_leg_mesh = MeshInstance3D.new()
	bl_leg_mesh.mesh = leg_mesh
	bl_leg_mesh.material_override = fur_mat
	bl_leg_mesh.position = Vector3(0, -0.175 * scale_factor, 0)
	bl_leg.add_child(bl_leg_mesh)

	# Back right leg
	var br_leg = Node3D.new()
	br_leg.position = Vector3(0.1 * scale_factor, 0.35 * scale_factor, -0.2 * scale_factor)
	body_container.add_child(br_leg)

	var br_leg_mesh = MeshInstance3D.new()
	br_leg_mesh.mesh = leg_mesh
	br_leg_mesh.material_override = fur_mat
	br_leg_mesh.position = Vector3(0, -0.175 * scale_factor, 0)
	br_leg.add_child(br_leg_mesh)

	# Tail (small)
	var tail = MeshInstance3D.new()
	var tail_mesh = SphereMesh.new()
	tail_mesh.radius = 0.04 * scale_factor
	tail_mesh.height = 0.06 * scale_factor
	tail.mesh = tail_mesh
	tail.material_override = belly_mat
	tail.position = Vector3(0, 0.55 * scale_factor, -0.32 * scale_factor)
	body_container.add_child(tail)

	head_base_height = 0.85 * scale_factor
