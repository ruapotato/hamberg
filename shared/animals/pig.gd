extends "res://shared/animals/passive_animal.gd"

## Pig - Plump farm animal
## Found in meadow biomes
## Drops raw pork when killed

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with pig-specific values
	enemy_name = "Pig"
	max_health = 35.0  # Pigs are tougher
	move_speed = 2.5  # Pigs are slower
	strafe_speed = 2.0
	loot_table = {"raw_pork": 3}

	print("[Pig] Pig ready (network_id=%d)" % network_id)

## Build pig body - round, pink, stubby legs
## If BodyContainer exists in TSCN with children, uses that mesh instead
func _setup_body() -> void:
	# Check if BodyContainer already exists in the scene (from TSCN)
	var existing_container = get_node_or_null("BodyContainer")
	if existing_container and existing_container.get_child_count() > 0:
		# Use the mesh from TSCN
		body_container = existing_container
		head_base_height = 0.4 * 0.8  # Default pig height
		print("[Pig] Using custom mesh from TSCN")
		return

	# Create procedural mesh if no custom mesh provided
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI  # Face -Z direction (forward in Godot)
	add_child(body_container)

	var scale_factor: float = 0.8

	# Pig materials - pink
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.95, 0.75, 0.7, 1)  # Pink

	var nose_mat = StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.9, 0.6, 0.55, 1)  # Darker pink nose

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.1, 0.05, 0.0, 1)  # Dark eyes

	# Body (round horizontal shape)
	torso = MeshInstance3D.new()
	var body_mesh = SphereMesh.new()
	body_mesh.radius = 0.25 * scale_factor
	body_mesh.height = 0.45 * scale_factor
	torso.mesh = body_mesh
	torso.material_override = skin_mat
	torso.position = Vector3(0, 0.35 * scale_factor, 0)
	torso.scale = Vector3(1, 0.8, 1.3)  # Stretch horizontally
	body_container.add_child(torso)

	# Head
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.12 * scale_factor
	head_mesh.height = 0.22 * scale_factor
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0, 0.4 * scale_factor, 0.3 * scale_factor)
	body_container.add_child(head)

	# Snout (cylindrical)
	var snout = MeshInstance3D.new()
	var snout_mesh = CylinderMesh.new()
	snout_mesh.top_radius = 0.045 * scale_factor
	snout_mesh.bottom_radius = 0.05 * scale_factor
	snout_mesh.height = 0.08 * scale_factor
	snout.mesh = snout_mesh
	snout.material_override = nose_mat
	snout.position = Vector3(0, -0.02 * scale_factor, 0.12 * scale_factor)
	snout.rotation.x = PI / 2
	head.add_child(snout)

	# Nostrils (two dark spots)
	var nostril_mesh = SphereMesh.new()
	nostril_mesh.radius = 0.012 * scale_factor
	nostril_mesh.height = 0.024 * scale_factor

	var left_nostril = MeshInstance3D.new()
	left_nostril.mesh = nostril_mesh
	left_nostril.material_override = eye_mat
	left_nostril.position = Vector3(-0.02 * scale_factor, 0, 0.04 * scale_factor)
	snout.add_child(left_nostril)

	var right_nostril = MeshInstance3D.new()
	right_nostril.mesh = nostril_mesh
	right_nostril.material_override = eye_mat
	right_nostril.position = Vector3(0.02 * scale_factor, 0, 0.04 * scale_factor)
	snout.add_child(right_nostril)

	# Eyes
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.015 * scale_factor
	eye_mesh.height = 0.03 * scale_factor

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.06 * scale_factor, 0.04 * scale_factor, 0.08 * scale_factor)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.06 * scale_factor, 0.04 * scale_factor, 0.08 * scale_factor)
	head.add_child(right_eye)

	# Ears (floppy triangles)
	var ear_mesh = PrismMesh.new()
	ear_mesh.size = Vector3(0.08, 0.06, 0.02) * scale_factor

	var left_ear = MeshInstance3D.new()
	left_ear.mesh = ear_mesh
	left_ear.material_override = skin_mat
	left_ear.position = Vector3(-0.08 * scale_factor, 0.1 * scale_factor, 0.02 * scale_factor)
	left_ear.rotation.z = 0.5
	left_ear.rotation.x = 0.3
	head.add_child(left_ear)

	var right_ear = MeshInstance3D.new()
	right_ear.mesh = ear_mesh
	right_ear.material_override = skin_mat
	right_ear.position = Vector3(0.08 * scale_factor, 0.1 * scale_factor, 0.02 * scale_factor)
	right_ear.rotation.z = -0.5
	right_ear.rotation.x = 0.3
	head.add_child(right_ear)

	# Legs (4 stubby legs)
	var leg_mesh = CapsuleMesh.new()
	leg_mesh.radius = 0.04 * scale_factor
	leg_mesh.height = 0.2 * scale_factor

	# Front left leg
	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.12 * scale_factor, 0.2 * scale_factor, 0.15 * scale_factor)
	body_container.add_child(left_leg)

	var fl_leg_mesh = MeshInstance3D.new()
	fl_leg_mesh.mesh = leg_mesh
	fl_leg_mesh.material_override = skin_mat
	fl_leg_mesh.position = Vector3(0, -0.1 * scale_factor, 0)
	left_leg.add_child(fl_leg_mesh)

	# Front right leg
	right_leg = Node3D.new()
	right_leg.position = Vector3(0.12 * scale_factor, 0.2 * scale_factor, 0.15 * scale_factor)
	body_container.add_child(right_leg)

	var fr_leg_mesh = MeshInstance3D.new()
	fr_leg_mesh.mesh = leg_mesh
	fr_leg_mesh.material_override = skin_mat
	fr_leg_mesh.position = Vector3(0, -0.1 * scale_factor, 0)
	right_leg.add_child(fr_leg_mesh)

	# Back left leg
	var bl_leg = Node3D.new()
	bl_leg.position = Vector3(-0.12 * scale_factor, 0.2 * scale_factor, -0.18 * scale_factor)
	body_container.add_child(bl_leg)

	var bl_leg_mesh = MeshInstance3D.new()
	bl_leg_mesh.mesh = leg_mesh
	bl_leg_mesh.material_override = skin_mat
	bl_leg_mesh.position = Vector3(0, -0.1 * scale_factor, 0)
	bl_leg.add_child(bl_leg_mesh)

	# Back right leg
	var br_leg = Node3D.new()
	br_leg.position = Vector3(0.12 * scale_factor, 0.2 * scale_factor, -0.18 * scale_factor)
	body_container.add_child(br_leg)

	var br_leg_mesh = MeshInstance3D.new()
	br_leg_mesh.mesh = leg_mesh
	br_leg_mesh.material_override = skin_mat
	br_leg_mesh.position = Vector3(0, -0.1 * scale_factor, 0)
	br_leg.add_child(br_leg_mesh)

	# Curly tail
	var tail = MeshInstance3D.new()
	var tail_mesh = TorusMesh.new()
	tail_mesh.inner_radius = 0.01 * scale_factor
	tail_mesh.outer_radius = 0.03 * scale_factor
	tail.mesh = tail_mesh
	tail.material_override = skin_mat
	tail.position = Vector3(0, 0.4 * scale_factor, -0.3 * scale_factor)
	tail.rotation.x = PI / 2
	body_container.add_child(tail)

	head_base_height = 0.4 * scale_factor
