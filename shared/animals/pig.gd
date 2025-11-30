extends "res://shared/animals/passive_animal.gd"

## Flying Pig - Whimsical winged pig that flies around
## Found floating in meadow biomes
## Drops raw pork when killed

# Wing references for animation
var left_wing: Node3D = null
var right_wing: Node3D = null

# Flying parameters
var fly_height: float = 4.0  # Target height above ground
var bob_timer: float = 0.0
var bob_speed: float = 2.0  # How fast to bob up and down
var bob_amount: float = 0.3  # How much to bob
var wing_flap_speed: float = 8.0  # Wing flapping speed
var current_fly_direction: Vector3 = Vector3.ZERO
var fly_direction_timer: float = 0.0
var target_altitude: float = 4.0

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with pig-specific values
	enemy_name = "Flying Pig"
	max_health = 35.0
	move_speed = 3.5  # Faster in the air
	strafe_speed = 3.0
	loot_table = {"raw_pork": 3, "pig_leather": 2}

	# Randomize starting direction
	var angle = randf() * TAU
	current_fly_direction = Vector3(cos(angle), 0, sin(angle))
	fly_direction_timer = randf_range(3.0, 6.0)

	# Randomize target altitude
	target_altitude = randf_range(3.0, 6.0)

	print("[Pig] Flying pig ready (network_id=%d)" % network_id)

## Build pig body - round, pink, stubby legs, with whimsical wings!
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

	# Wing material - pure white/blank for whimsy
	var wing_mat = StandardMaterial3D.new()
	wing_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # Pure white
	wing_mat.metallic = 0.0
	wing_mat.roughness = 0.8

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

	# Legs (4 stubby legs - dangling while flying)
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

	# === WINGS! ===
	# Create whimsical white wings attached to the sides of the body

	# Left wing pivot (for flapping animation)
	left_wing = Node3D.new()
	left_wing.name = "LeftWing"
	left_wing.position = Vector3(-0.18 * scale_factor, 0.4 * scale_factor, 0)
	body_container.add_child(left_wing)

	# Left wing mesh - elongated ellipsoid shape
	var left_wing_mesh = MeshInstance3D.new()
	var wing_shape = SphereMesh.new()
	wing_shape.radius = 0.15 * scale_factor
	wing_shape.height = 0.08 * scale_factor
	left_wing_mesh.mesh = wing_shape
	left_wing_mesh.material_override = wing_mat
	left_wing_mesh.scale = Vector3(1.8, 0.3, 1.0)  # Flatten and elongate
	left_wing_mesh.position = Vector3(-0.1 * scale_factor, 0, 0)
	left_wing.add_child(left_wing_mesh)

	# Left wing feather tip
	var left_tip = MeshInstance3D.new()
	var tip_shape = SphereMesh.new()
	tip_shape.radius = 0.08 * scale_factor
	tip_shape.height = 0.04 * scale_factor
	left_tip.mesh = tip_shape
	left_tip.material_override = wing_mat
	left_tip.scale = Vector3(1.5, 0.3, 0.8)
	left_tip.position = Vector3(-0.22 * scale_factor, 0, 0)
	left_wing.add_child(left_tip)

	# Right wing pivot (for flapping animation)
	right_wing = Node3D.new()
	right_wing.name = "RightWing"
	right_wing.position = Vector3(0.18 * scale_factor, 0.4 * scale_factor, 0)
	body_container.add_child(right_wing)

	# Right wing mesh - elongated ellipsoid shape
	var right_wing_mesh = MeshInstance3D.new()
	right_wing_mesh.mesh = wing_shape
	right_wing_mesh.material_override = wing_mat
	right_wing_mesh.scale = Vector3(1.8, 0.3, 1.0)
	right_wing_mesh.position = Vector3(0.1 * scale_factor, 0, 0)
	right_wing.add_child(right_wing_mesh)

	# Right wing feather tip
	var right_tip = MeshInstance3D.new()
	right_tip.mesh = tip_shape
	right_tip.material_override = wing_mat
	right_tip.scale = Vector3(1.5, 0.3, 0.8)
	right_tip.position = Vector3(0.22 * scale_factor, 0, 0)
	right_wing.add_child(right_tip)

	head_base_height = 0.4 * scale_factor

## Override physics process for flying and wing animation
func _physics_process(delta: float) -> void:
	# Call parent physics first
	super._physics_process(delta)

	# Animate wings (flapping)
	bob_timer += delta * wing_flap_speed
	if left_wing and right_wing:
		var flap_angle = sin(bob_timer) * 0.5  # Flap up and down
		left_wing.rotation.z = flap_angle + 0.3  # Slight upward angle
		right_wing.rotation.z = -flap_angle - 0.3

## Override idle behavior to fly around instead of walking
func _update_idle(delta: float) -> void:
	# Update flight direction timer
	fly_direction_timer -= delta
	if fly_direction_timer <= 0:
		fly_direction_timer = randf_range(3.0, 7.0)
		# Pick a new random direction
		var angle = randf() * TAU
		current_fly_direction = Vector3(cos(angle), 0, sin(angle))
		# Also occasionally change altitude
		target_altitude = randf_range(3.0, 6.0)

	# Fly in current direction
	velocity.x = current_fly_direction.x * move_speed
	velocity.z = current_fly_direction.z * move_speed

	# Maintain altitude with gentle bobbing
	var bob_offset = sin(bob_timer * bob_speed * 0.3) * bob_amount
	var current_height = global_position.y
	var height_diff = (target_altitude + bob_offset) - current_height
	velocity.y = height_diff * 2.0  # Smooth altitude adjustment

	# Face movement direction
	if velocity.length() > 0.1:
		_face_movement()

	# Set AI state for animation sync
	ai_state = AIState.IDLE

## Override fleeing to fly away
func _update_fleeing(delta: float) -> void:
	# Update direction change timer
	direction_change_timer -= delta

	# Periodically change direction for erratic flee behavior
	if direction_change_timer <= 0:
		direction_change_timer = randf_range(MIN_DIRECTION_CHANGE_TIME, MAX_DIRECTION_CHANGE_TIME)

		# Start with away-from-player direction, then add random offset
		if flee_from_player and is_instance_valid(flee_from_player):
			var away_dir = global_position - flee_from_player.global_position
			away_dir.y = 0
			if away_dir.length() > 0.1:
				flee_target = away_dir.normalized()
			else:
				var angle = randf() * TAU
				flee_target = Vector3(cos(angle), 0, sin(angle))

		# Add random angle offset (can veer left or right significantly)
		var angle_offset = randf_range(-DIRECTION_CHANGE_ANGLE, DIRECTION_CHANGE_ANGLE)
		flee_target = flee_target.rotated(Vector3.UP, angle_offset)

		# Fly higher when fleeing!
		target_altitude = randf_range(6.0, 10.0)

	# Run in flee direction
	var flee_dir = flee_target.normalized()
	var flee_speed = move_speed * FLEE_SPEED_MULTIPLIER

	velocity.x = flee_dir.x * flee_speed
	velocity.z = flee_dir.z * flee_speed

	# Maintain higher altitude when fleeing with bobbing
	var bob_offset = sin(bob_timer * bob_speed * 0.3) * bob_amount
	var current_height = global_position.y
	var height_diff = (target_altitude + bob_offset) - current_height
	velocity.y = height_diff * 3.0  # Faster altitude adjustment when fleeing

	_face_movement()

	# Use RETREATING state for animation sync (existing state in Enemy)
	ai_state = AIState.RETREATING
