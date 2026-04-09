extends "res://shared/animals/passive_animal.gd"

## SkyCuttlefish - Giant mysterious ambient creature that flies through the sky
## Visible from far away but unreachable in early game
## Inspired by the dragon in Breath of the Wild — a silent, awe-inspiring presence
## Flies at very high altitude in slow sweeping curves

# Flying parameters
var initial_spawn_y: float = 0.0
var fly_height: float = 70.0  # Very high above terrain
var fly_direction: Vector3 = Vector3.ZERO
var fly_direction_timer: float = 0.0
const FLY_DIRECTION_CHANGE_MIN: float = 15.0  # Long sweeping paths
const FLY_DIRECTION_CHANGE_MAX: float = 30.0
const FLY_SPEED: float = 1.2  # Slow, majestic movement
const FLY_TURN_SPEED: float = 0.3  # Very gentle turning

# Curved path tracking
var path_angle: float = 0.0  # Current angle for circular/curved path
var path_curve_rate: float = 0.02  # How quickly the path curves (radians/sec)

# Animation time
var anim_time: float = 0.0

# Procedural body parts for animation
var tentacles: Array[Node3D] = []
var body_segments: Array[MeshInstance3D] = []
var left_eye_mesh: MeshInstance3D = null
var right_eye_mesh: MeshInstance3D = null
var mantle_segments: Array[MeshInstance3D] = []

# Body scale (giant creature visible from far away)
const BODY_SCALE: float = 4.0

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Override with cuttlefish-specific values
	enemy_name = "SkyCuttlefish"
	max_health = 9999.0
	health = max_health
	move_speed = FLY_SPEED
	strafe_speed = FLY_SPEED

	# No loot (or legendary if somehow killed)
	loot_table = {}
	rare_loot_table = {}

	# Not skittish — it ignores players entirely
	is_skittish = false
	flee_detection_range = 0.0

	# Massive detection range so it doesn't despawn easily
	detection_range = 200.0

	# Very resistant to everything (ancient creature)
	damage_resistances = {
		WeaponData.DamageType.SLASH: 0.3,
		WeaponData.DamageType.BLUNT: 0.3,
		WeaponData.DamageType.PIERCE: 0.3,
		WeaponData.DamageType.FIRE: 0.5,
		WeaponData.DamageType.ICE: 0.5,
		WeaponData.DamageType.POISON: 0.1,
	}

	# No idle sounds — silent and mysterious
	_idle_sound_interval = 999999.0

	# Randomize fly height
	fly_height = randf_range(60.0, 80.0)

	# Pick initial random direction and curve
	path_angle = randf() * TAU
	fly_direction = Vector3(cos(path_angle), 0, sin(path_angle))
	fly_direction_timer = randf_range(FLY_DIRECTION_CHANGE_MIN, FLY_DIRECTION_CHANGE_MAX)

	# Randomize curve direction (clockwise or counter-clockwise)
	path_curve_rate = randf_range(0.01, 0.03) * (1.0 if randf() > 0.5 else -1.0)

	initial_spawn_y = 0.0

	# Randomize animation start time so multiple cuttlefish look different
	anim_time = randf() * 100.0

	print("[SkyCuttlefish] Sky cuttlefish ready (network_id=%d)" % network_id)

func _get_idle_sound() -> String:
	return ""  # Silent

func _get_death_sound() -> String:
	return ""  # Silent

## Override idle to fly in slow sweeping curves at high altitude
func _update_idle(delta: float) -> void:
	# No idle sounds for cuttlefish

	# Slowly curve the path over time
	path_angle += path_curve_rate * delta
	fly_direction = Vector3(cos(path_angle), 0, sin(path_angle))

	# Occasionally change curve direction for variety
	fly_direction_timer -= delta
	if fly_direction_timer <= 0:
		fly_direction_timer = randf_range(FLY_DIRECTION_CHANGE_MIN, FLY_DIRECTION_CHANGE_MAX)
		path_curve_rate = randf_range(0.01, 0.03) * (1.0 if randf() > 0.5 else -1.0)

	# Move in fly direction
	velocity.x = fly_direction.x * FLY_SPEED
	velocity.z = fly_direction.z * FLY_SPEED

	# Maintain fly height
	_maintain_fly_height()

	_face_movement()
	ai_state = AIState.IDLE

## Override fleeing — cuttlefish doesn't really flee, just keeps flying
func _update_fleeing(delta: float) -> void:
	# Just continue normal flight, ignore threats
	flee_timer = 0.0
	_update_idle(delta)

## Keep cuttlefish at its target fly height above terrain
func _maintain_fly_height() -> void:
	if initial_spawn_y == 0.0 and global_position.y > 0.1:
		initial_spawn_y = global_position.y - fly_height

	var target_y = initial_spawn_y + fly_height
	if global_position.y < target_y - 2.0:
		velocity.y = 1.5
	elif global_position.y > target_y + 2.0:
		velocity.y = -0.5
	else:
		velocity.y = sin(anim_time * 0.3) * 0.2  # Gentle bobbing

## Override host AI to skip gravity (cuttlefish flies!)
func _run_host_ai(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if throw_cooldown > 0:
		throw_cooldown -= delta

	state_timer += delta

	# NO gravity for flying creatures

	# Run AI state machine
	_update_ai(delta)

	# Smooth rotation
	_update_rotation(delta)

	# Move
	move_and_slide()

## Animate body parts in physics process
func _physics_process(delta: float) -> void:
	anim_time += delta

	# Animate tentacles — wave with sin(time + offset)
	for i in range(tentacles.size()):
		var tentacle = tentacles[i]
		if not is_instance_valid(tentacle):
			continue
		var offset = float(i) * 0.8  # Phase offset per tentacle
		var wave_x = sin(anim_time * 1.5 + offset) * 0.3
		var wave_y = cos(anim_time * 1.2 + offset * 1.3) * 0.15
		tentacle.rotation.x = wave_x
		tentacle.rotation.z = wave_y

	# Animate body segments — undulation like swimming cuttlefish
	for i in range(body_segments.size()):
		var segment = body_segments[i]
		if not is_instance_valid(segment):
			continue
		var offset = float(i) * 0.6
		var undulate = sin(anim_time * 1.0 + offset) * 0.08
		segment.position.y = segment.get_meta("base_y", 0.0) + undulate

	# Animate mantle segments — flowing wave
	for i in range(mantle_segments.size()):
		var segment = mantle_segments[i]
		if not is_instance_valid(segment):
			continue
		var offset = float(i) * 0.5
		var wave = sin(anim_time * 0.8 + offset) * 0.12
		var scale_pulse = 1.0 + sin(anim_time * 0.6 + offset) * 0.05
		segment.position.x = segment.get_meta("base_x", 0.0) + wave
		segment.scale.x = scale_pulse
		segment.scale.z = scale_pulse

## Build the giant cuttlefish body procedurally
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI  # Face -Z direction (forward in Godot)
	body_container.scale = Vector3(BODY_SCALE, BODY_SCALE, BODY_SCALE)
	add_child(body_container)

	# === MATERIALS ===

	# Body material — pink (#ff0093) with blue emission
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color("#ff0093")
	body_mat.emission_enabled = true
	body_mat.emission = Color("#0014ff")
	body_mat.emission_energy_multiplier = 0.3
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.albedo_color.a = 0.9

	# Eye material — yellow (#ffeb00) with strong emission (glowing eyes)
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color("#ffeb00")
	eye_mat.emission_enabled = true
	eye_mat.emission = Color("#ffeb00")
	eye_mat.emission_energy_multiplier = 2.0

	# Tentacle material — pink body with green tips
	var tentacle_mat = StandardMaterial3D.new()
	tentacle_mat.albedo_color = Color("#ff0093")
	tentacle_mat.emission_enabled = true
	tentacle_mat.emission = Color("#0014ff")
	tentacle_mat.emission_energy_multiplier = 0.2

	# Tentacle tip material — green glow (#00ff6c)
	var tip_mat = StandardMaterial3D.new()
	tip_mat.albedo_color = Color("#00ff6c")
	tip_mat.emission_enabled = true
	tip_mat.emission = Color("#00ff6c")
	tip_mat.emission_energy_multiplier = 1.5

	# Mantle material — slightly translucent pink
	var mantle_mat = StandardMaterial3D.new()
	mantle_mat.albedo_color = Color("#ff0093")
	mantle_mat.albedo_color.a = 0.7
	mantle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mantle_mat.emission_enabled = true
	mantle_mat.emission = Color("#0014ff")
	mantle_mat.emission_energy_multiplier = 0.4

	# === MAIN BODY (elongated oval) ===
	torso = MeshInstance3D.new()
	var body_mesh = SphereMesh.new()
	body_mesh.radius = 0.5
	body_mesh.height = 1.8  # Elongated
	torso.mesh = body_mesh
	torso.material_override = body_mat
	torso.position = Vector3(0, 0.5, 0)
	torso.rotation.x = PI * 0.5  # Rotate so elongation goes along Z (forward)
	body_container.add_child(torso)
	body_segments.append(torso)
	torso.set_meta("base_y", 0.5)

	# === BODY SEGMENTS (undulating midsection) ===
	for i in range(4):
		var segment = MeshInstance3D.new()
		var seg_mesh = SphereMesh.new()
		var t = float(i) / 3.0
		seg_mesh.radius = 0.45 - t * 0.1  # Taper toward rear
		seg_mesh.height = 0.4
		segment.mesh = seg_mesh
		segment.material_override = body_mat
		var z_pos = -0.5 - float(i) * 0.35  # Behind main body
		segment.position = Vector3(0, 0.5, z_pos)
		segment.set_meta("base_y", 0.5)
		body_container.add_child(segment)
		body_segments.append(segment)

	# === HEAD (front of body) ===
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.4
	head_mesh.height = 0.7
	head.mesh = head_mesh
	head.material_override = body_mat
	head.position = Vector3(0, 0.5, 0.9)
	body_container.add_child(head)

	# === EYES (large, glowing yellow) ===
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.1
	eye_mesh.height = 0.12

	left_eye_mesh = MeshInstance3D.new()
	left_eye_mesh.mesh = eye_mesh
	left_eye_mesh.material_override = eye_mat
	left_eye_mesh.position = Vector3(-0.25, 0.08, 0.25)
	head.add_child(left_eye_mesh)

	right_eye_mesh = MeshInstance3D.new()
	right_eye_mesh.mesh = eye_mesh
	right_eye_mesh.material_override = eye_mat
	right_eye_mesh.position = Vector3(0.25, 0.08, 0.25)
	head.add_child(right_eye_mesh)

	# === FACE TENTACLES (8 thin cylinders at the front) ===
	for i in range(8):
		var tentacle_root = Node3D.new()
		tentacle_root.name = "Tentacle_%d" % i

		# Arrange in a ring around the face
		var angle = (float(i) / 8.0) * TAU
		var ring_radius = 0.2
		var x_off = cos(angle) * ring_radius
		var y_off = sin(angle) * ring_radius
		tentacle_root.position = Vector3(x_off, y_off - 0.05, 0.35)

		# Tentacle shaft
		var shaft = MeshInstance3D.new()
		var shaft_mesh = CylinderMesh.new()
		shaft_mesh.top_radius = 0.02
		shaft_mesh.bottom_radius = 0.035
		shaft_mesh.height = 0.6
		shaft.mesh = shaft_mesh
		shaft.material_override = tentacle_mat
		shaft.position = Vector3(0, 0, 0.3)
		shaft.rotation.x = PI * 0.5  # Point forward
		tentacle_root.add_child(shaft)

		# Tentacle tip (green glow)
		var tip = MeshInstance3D.new()
		var tip_mesh = SphereMesh.new()
		tip_mesh.radius = 0.03
		tip_mesh.height = 0.06
		tip.mesh = tip_mesh
		tip.material_override = tip_mat
		tip.position = Vector3(0, 0, 0.6)
		tentacle_root.add_child(tip)

		head.add_child(tentacle_root)
		tentacles.append(tentacle_root)

	# === MANTLE FINS (flowing side fins) ===
	for side in [-1.0, 1.0]:
		for i in range(3):
			var fin = MeshInstance3D.new()
			var fin_mesh = BoxMesh.new()
			var t = float(i) / 2.0
			fin_mesh.size = Vector3(0.6 - t * 0.15, 0.03, 0.3 - t * 0.05)
			fin.mesh = fin_mesh
			fin.material_override = mantle_mat
			var x_pos = side * (0.45 + t * 0.05)
			var z_pos = -0.2 - float(i) * 0.35
			fin.position = Vector3(x_pos, 0.5, z_pos)
			fin.set_meta("base_x", x_pos)
			body_container.add_child(fin)
			mantle_segments.append(fin)

	# === REAR TAIL (tapered end) ===
	var tail = MeshInstance3D.new()
	var tail_mesh = SphereMesh.new()
	tail_mesh.radius = 0.2
	tail_mesh.height = 0.8
	tail.mesh = tail_mesh
	tail.material_override = body_mat
	tail.position = Vector3(0, 0.5, -1.9)
	tail.rotation.x = PI * 0.5
	body_container.add_child(tail)
	body_segments.append(tail)
	tail.set_meta("base_y", 0.5)

	head_base_height = 0.5
