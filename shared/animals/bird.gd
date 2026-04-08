extends "res://shared/animals/passive_animal.gd"

## Bird - Small ambient flying wildlife
## Flies in the air, never touches ground
## Very skittish - flees quickly when players approach
## Spawns in all biomes during daytime, despawns at night

# Spawn height tracking (set after added to tree)
var initial_spawn_y: float = 0.0

# Flying parameters
var fly_height: float = 10.0  # Target height above terrain
var fly_direction: Vector3 = Vector3.ZERO
var fly_direction_timer: float = 0.0
const FLY_DIRECTION_CHANGE_MIN: float = 3.0
const FLY_DIRECTION_CHANGE_MAX: float = 8.0
const FLY_SPEED: float = 2.0
const FLY_FLEE_SPEED: float = 8.0
const FLY_MIN_HEIGHT: float = 5.0
const FLY_MAX_HEIGHT: float = 15.0

func _ready() -> void:
	# Call parent ready first to set defaults
	super._ready()

	# Then override with bird-specific values
	enemy_name = "Bird"
	max_health = 5.0  # One hit kills them
	health = max_health
	move_speed = FLY_SPEED
	strafe_speed = FLY_SPEED

	loot_table = {"plant_fiber": 1}

	# Birds are very skittish - flee when players get close
	is_skittish = true
	flee_detection_range = 15.0  # Birds are very alert

	# Randomize fly height
	fly_height = randf_range(FLY_MIN_HEIGHT, FLY_MAX_HEIGHT)

	# Pick initial random direction
	var angle = randf() * TAU
	fly_direction = Vector3(cos(angle), 0, sin(angle))
	fly_direction_timer = randf_range(FLY_DIRECTION_CHANGE_MIN, FLY_DIRECTION_CHANGE_MAX)

	# Faster idle sound interval for birds (birdsong)
	_idle_sound_interval = 5.0

	# Store initial spawn Y for height reference (set after position is assigned by spawner)
	# We'll capture it on first physics frame
	initial_spawn_y = 0.0

	print("[Bird] Bird ready (network_id=%d)" % network_id)

func _get_idle_sound() -> String:
	return "birds_ambient"

func _get_death_sound() -> String:
	return "flapping"

## Override idle to fly in the air with random direction changes
func _update_idle(delta: float) -> void:
	# Play idle sounds (birdsong)
	_idle_sound_timer -= delta
	if _idle_sound_timer <= 0:
		_idle_sound_timer = _idle_sound_interval + randf_range(-1.0, 2.0)
		var idle_sound := _get_idle_sound()
		if idle_sound != "":
			var players = EnemyAI._get_cached_players(get_tree())
			var player_nearby := false
			for p in players:
				if is_instance_valid(p) and global_position.distance_to(p.global_position) < 30.0:
					player_nearby = true
					break
			if player_nearby:
				SoundManager.play_sound_varied(idle_sound, global_position, -4.0, 0.15)

	# Check for nearby players if skittish
	if is_skittish and is_host:
		var nearby_player = _detect_nearby_player()
		if nearby_player:
			_start_fleeing_from(nearby_player)
			return

	# Direction change timer
	fly_direction_timer -= delta
	if fly_direction_timer <= 0:
		fly_direction_timer = randf_range(FLY_DIRECTION_CHANGE_MIN, FLY_DIRECTION_CHANGE_MAX)
		var angle = randf() * TAU
		fly_direction = Vector3(cos(angle), 0, sin(angle))

	# Move in fly direction
	velocity.x = fly_direction.x * FLY_SPEED
	velocity.z = fly_direction.z * FLY_SPEED

	# Maintain fly height (counteract gravity)
	_maintain_fly_height()

	_face_movement()
	ai_state = AIState.IDLE

## Override fleeing to fly away fast and gain altitude
func _update_fleeing(delta: float) -> void:
	# Update direction change timer
	direction_change_timer -= delta

	if direction_change_timer <= 0:
		direction_change_timer = randf_range(MIN_DIRECTION_CHANGE_TIME, MAX_DIRECTION_CHANGE_TIME)

		if flee_from_player and is_instance_valid(flee_from_player):
			var away_dir = global_position - flee_from_player.global_position
			away_dir.y = 0
			if away_dir.length() > 0.1:
				flee_target = away_dir.normalized()
			else:
				var angle = randf() * TAU
				flee_target = Vector3(cos(angle), 0, sin(angle))

		var angle_offset = randf_range(-DIRECTION_CHANGE_ANGLE, DIRECTION_CHANGE_ANGLE)
		flee_target = flee_target.rotated(Vector3.UP, angle_offset)

	# Fly away fast
	var flee_dir = flee_target.normalized()
	velocity.x = flee_dir.x * FLY_FLEE_SPEED
	velocity.z = flee_dir.z * FLY_FLEE_SPEED

	# Gain altitude when fleeing
	velocity.y = 3.0

	_face_movement()
	ai_state = AIState.RETREATING

## Keep bird at its target fly height above terrain
func _maintain_fly_height() -> void:
	# Capture initial spawn Y on first frame (spawner sets position after _ready)
	if initial_spawn_y == 0.0 and global_position.y > 0.1:
		initial_spawn_y = global_position.y - fly_height  # Approximate terrain height

	var target_y = initial_spawn_y + fly_height
	if global_position.y < target_y - 1.0:
		velocity.y = 2.0  # Fly upward
	elif global_position.y > target_y + 1.0:
		velocity.y = -1.0  # Drift downward slightly
	else:
		velocity.y = 0.0  # Hover

## Override host AI to skip gravity (birds fly!)
func _run_host_ai(delta: float) -> void:
	# Update cooldowns (from base)
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if throw_cooldown > 0:
		throw_cooldown -= delta

	state_timer += delta

	# NO gravity for birds - they fly!

	# Run AI state machine
	_update_ai(delta)

	# Smooth rotation
	_update_rotation(delta)

	# Move
	move_and_slide()

## Build bird body - small sphere body with two box wings
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI  # Face -Z direction (forward in Godot)
	add_child(body_container)

	# Bird body material - blue tint (matching game palette)
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.3, 0.45, 0.7, 1)  # Blue-grey

	var wing_mat = StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.2, 0.35, 0.6, 1)  # Darker blue wings

	var beak_mat = StandardMaterial3D.new()
	beak_mat.albedo_color = Color(0.8, 0.6, 0.2, 1)  # Orange beak

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.05, 1)  # Dark eyes

	# Body (small sphere)
	torso = MeshInstance3D.new()
	var body_mesh = SphereMesh.new()
	body_mesh.radius = 0.08
	body_mesh.height = 0.16
	torso.mesh = body_mesh
	torso.material_override = body_mat
	torso.position = Vector3(0, 0.1, 0)
	body_container.add_child(torso)

	# Head (smaller sphere)
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.05
	head_mesh.height = 0.1
	head.mesh = head_mesh
	head.material_override = body_mat
	head.position = Vector3(0, 0.16, 0.07)
	body_container.add_child(head)

	# Beak
	var beak = MeshInstance3D.new()
	var beak_mesh = BoxMesh.new()
	beak_mesh.size = Vector3(0.02, 0.015, 0.04)
	beak.mesh = beak_mesh
	beak.material_override = beak_mat
	beak.position = Vector3(0, -0.01, 0.06)
	head.add_child(beak)

	# Eyes
	var eye_mesh = SphereMesh.new()
	eye_mesh.radius = 0.008
	eye_mesh.height = 0.016

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.03, 0.01, 0.03)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.03, 0.01, 0.03)
	head.add_child(right_eye)

	# Left wing (box mesh)
	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.08, 0.12, 0)
	body_container.add_child(left_arm)

	var left_wing_mesh = MeshInstance3D.new()
	var lw_mesh = BoxMesh.new()
	lw_mesh.size = Vector3(0.12, 0.01, 0.06)
	left_wing_mesh.mesh = lw_mesh
	left_wing_mesh.material_override = wing_mat
	left_wing_mesh.position = Vector3(-0.06, 0, 0)
	left_arm.add_child(left_wing_mesh)

	# Right wing (box mesh)
	right_arm = Node3D.new()
	right_arm.position = Vector3(0.08, 0.12, 0)
	body_container.add_child(right_arm)

	var right_wing_mesh = MeshInstance3D.new()
	var rw_mesh = BoxMesh.new()
	rw_mesh.size = Vector3(0.12, 0.01, 0.06)
	right_wing_mesh.mesh = rw_mesh
	right_wing_mesh.material_override = wing_mat
	right_wing_mesh.position = Vector3(0.06, 0, 0)
	right_arm.add_child(right_wing_mesh)

	# Tail
	var tail = MeshInstance3D.new()
	var tail_mesh = BoxMesh.new()
	tail_mesh.size = Vector3(0.03, 0.01, 0.05)
	tail.mesh = tail_mesh
	tail.material_override = wing_mat
	tail.position = Vector3(0, 0.1, -0.1)
	body_container.add_child(tail)

	head_base_height = 0.16
