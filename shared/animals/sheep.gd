extends "res://shared/animals/passive_animal.gd"

## Sheep - Fluffy wool-covered animal
## Found in meadow biomes
## Drops raw mutton when killed

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with sheep-specific values
	enemy_name = "Sheep"
	max_health = 30.0
	move_speed = 2.8
	strafe_speed = 2.2
	loot_table = {"raw_mutton": 2}

	print("[Sheep] Sheep ready (network_id=%d)" % network_id)

## Build sheep body - fluffy white wool, black face and legs
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

	# Back left leg
	var bl_leg = Node3D.new()
	bl_leg.position = Vector3(-0.1 * scale_factor, 0.25 * scale_factor, -0.15 * scale_factor)
	body_container.add_child(bl_leg)

	var bl_leg_mesh = MeshInstance3D.new()
	bl_leg_mesh.mesh = leg_mesh
	bl_leg_mesh.material_override = skin_mat
	bl_leg_mesh.position = Vector3(0, -0.125 * scale_factor, 0)
	bl_leg.add_child(bl_leg_mesh)

	# Back right leg
	var br_leg = Node3D.new()
	br_leg.position = Vector3(0.1 * scale_factor, 0.25 * scale_factor, -0.15 * scale_factor)
	body_container.add_child(br_leg)

	var br_leg_mesh = MeshInstance3D.new()
	br_leg_mesh.mesh = leg_mesh
	br_leg_mesh.material_override = skin_mat
	br_leg_mesh.position = Vector3(0, -0.125 * scale_factor, 0)
	br_leg.add_child(br_leg_mesh)

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
