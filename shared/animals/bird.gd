extends "res://shared/animals/passive_animal.gd"

## Bird - Valheim-style ambient wildlife
## Mostly perched on the ground singing. Occasionally flies in swooping arcs.
## Very skittish — flees fast when players get within range.
## Spawns in all biomes during daytime.

# States
var is_perched: bool = true
var is_swooping: bool = false  # Flying between perch spots
var perch_timer: float = 0.0
var swoop_timer: float = 0.0
var swoop_target: Vector3 = Vector3.ZERO
var wing_time: float = 0.0

const PERCH_MIN: float = 10.0
const PERCH_MAX: float = 30.0
const SWOOP_SPEED: float = 8.0
const SWOOP_HEIGHT: float = 6.0  # Arc height during swoop
const SWOOP_DURATION: float = 3.0
const FLEE_SPEED: float = 14.0
const FLEE_CLIMB: float = 6.0
const CHIRP_MIN: float = 8.0
const CHIRP_MAX: float = 20.0

func _ready() -> void:
	super._ready()
	enemy_name = "Bird"
	max_health = 5.0
	health = max_health
	move_speed = SWOOP_SPEED
	strafe_speed = SWOOP_SPEED
	loot_table = {"plant_fiber": 1}

	is_skittish = true
	flee_detection_range = 8.0

	# Start perched
	is_perched = true
	perch_timer = randf_range(3.0, PERCH_MAX)
	_idle_sound_interval = randf_range(CHIRP_MIN, CHIRP_MAX)

	print("[Bird] Bird ready (network_id=%d)" % network_id)

func _get_idle_sound() -> String:
	return "birds_ambient"

func _get_death_sound() -> String:
	return "flapping"

func _update_idle(delta: float) -> void:
	# Chirp when perched
	_idle_sound_timer -= delta
	if _idle_sound_timer <= 0:
		_idle_sound_timer = randf_range(CHIRP_MIN, CHIRP_MAX)
		if is_perched:
			SoundManager.play_sound_varied("birds_ambient", global_position, -8.0, 0.25)

	# Check for nearby players
	if is_skittish and is_host:
		var nearby_player = _detect_nearby_player()
		if nearby_player:
			is_perched = false
			is_swooping = false
			_start_fleeing_from(nearby_player)
			return

	if is_perched:
		# Sit on ground, no movement
		velocity = Vector3.ZERO
		perch_timer -= delta
		if perch_timer <= 0:
			# Take off — pick a swoop target nearby
			is_perched = false
			is_swooping = true
			swoop_timer = 0.0
			var angle: float = randf() * TAU
			var dist: float = randf_range(15.0, 35.0)
			swoop_target = global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		ai_state = AIState.IDLE
		return

	if is_swooping:
		# Fly in an arc toward swoop_target
		swoop_timer += delta
		var t: float = swoop_timer / SWOOP_DURATION

		if t >= 1.0:
			# Arrived — land
			is_swooping = false
			is_perched = true
			perch_timer = randf_range(PERCH_MIN, PERCH_MAX)
			velocity = Vector3.ZERO
			ai_state = AIState.IDLE
			return

		# Horizontal movement toward target
		var to_target: Vector3 = swoop_target - global_position
		to_target.y = 0
		var horiz_dir: Vector3 = to_target.normalized()
		velocity.x = horiz_dir.x * SWOOP_SPEED
		velocity.z = horiz_dir.z * SWOOP_SPEED

		# Vertical arc: rise in first half, descend in second
		var arc_y: float = sin(t * PI) * SWOOP_HEIGHT
		var target_y: float = global_position.y  # Will be overridden
		# Get terrain height at current position for landing
		if t > 0.7:
			# Descend toward ground
			velocity.y = -4.0
		elif t < 0.3:
			# Climb
			velocity.y = 4.0
		else:
			# Cruise
			velocity.y = sin(t * PI * 2.0) * 1.0

		_face_movement()
		_flap_wings(delta)
		ai_state = AIState.IDLE
		return

	ai_state = AIState.IDLE

func _update_fleeing(delta: float) -> void:
	direction_change_timer -= delta
	if direction_change_timer <= 0:
		direction_change_timer = randf_range(1.0, 2.0)
		if flee_from_player and is_instance_valid(flee_from_player):
			var away_dir: Vector3 = global_position - flee_from_player.global_position
			away_dir.y = 0
			if away_dir.length() > 0.1:
				flee_target = away_dir.normalized()
			else:
				flee_target = Vector3(cos(randf() * TAU), 0, sin(randf() * TAU))
		flee_target = flee_target.rotated(Vector3.UP, randf_range(-0.5, 0.5))

	velocity.x = flee_target.x * FLEE_SPEED
	velocity.z = flee_target.z * FLEE_SPEED
	velocity.y = FLEE_CLIMB  # Climb fast when fleeing

	_face_movement()
	_flap_wings(delta)
	ai_state = AIState.RETREATING

func _flap_wings(delta: float) -> void:
	wing_time += delta * 12.0
	if left_arm:
		left_arm.rotation.z = sin(wing_time) * 0.6
	if right_arm:
		right_arm.rotation.z = -sin(wing_time) * 0.6

func _run_host_ai(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if throw_cooldown > 0:
		throw_cooldown -= delta
	state_timer += delta

	# No gravity when flying, apply gravity when perched (to settle on ground)
	if is_perched:
		velocity.y -= 20.0 * delta  # Gravity to stick to ground

	_update_ai(delta)
	_update_rotation(delta)
	move_and_slide()

func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.3, 0.45, 0.7, 1)
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.2, 0.35, 0.6, 1)
	var beak_mat := StandardMaterial3D.new()
	beak_mat.albedo_color = Color(0.8, 0.6, 0.2, 1)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.05, 1)

	torso = MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.08
	body_mesh.height = 0.16
	torso.mesh = body_mesh
	torso.material_override = body_mat
	torso.position = Vector3(0, 0.1, 0)
	body_container.add_child(torso)

	head = MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.05
	head_mesh.height = 0.1
	head.mesh = head_mesh
	head.material_override = body_mat
	head.position = Vector3(0, 0.16, 0.07)
	body_container.add_child(head)

	var beak := MeshInstance3D.new()
	var beak_mesh := BoxMesh.new()
	beak_mesh.size = Vector3(0.02, 0.015, 0.04)
	beak.mesh = beak_mesh
	beak.material_override = beak_mat
	beak.position = Vector3(0, -0.01, 0.06)
	head.add_child(beak)

	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.008
	eye_mesh.height = 0.016

	var left_eye := MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.03, 0.01, 0.03)
	head.add_child(left_eye)

	var right_eye := MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.03, 0.01, 0.03)
	head.add_child(right_eye)

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.08, 0.12, 0)
	body_container.add_child(left_arm)
	var lw := MeshInstance3D.new()
	var lw_mesh := BoxMesh.new()
	lw_mesh.size = Vector3(0.12, 0.01, 0.06)
	lw.mesh = lw_mesh
	lw.material_override = wing_mat
	lw.position = Vector3(-0.06, 0, 0)
	left_arm.add_child(lw)

	right_arm = Node3D.new()
	right_arm.position = Vector3(0.08, 0.12, 0)
	body_container.add_child(right_arm)
	var rw := MeshInstance3D.new()
	var rw_mesh := BoxMesh.new()
	rw_mesh.size = Vector3(0.12, 0.01, 0.06)
	rw.mesh = rw_mesh
	rw.material_override = wing_mat
	rw.position = Vector3(0.06, 0, 0)
	right_arm.add_child(rw)

	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.03, 0.01, 0.05)
	tail.mesh = tail_mesh
	tail.material_override = wing_mat
	tail.position = Vector3(0, 0.1, -0.1)
	body_container.add_child(tail)

	head_base_height = 0.16
