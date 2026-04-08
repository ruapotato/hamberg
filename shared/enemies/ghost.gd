extends "res://shared/enemies/enemy.gd"

## Ghost - Ethereal nighttime enemy
## Spawns only at night in all biomes
## Floats above ground, drifts toward players
## Semi-transparent with ghostly glow
## Disappears at dawn

# Spawn height tracking (captured on first physics frame)
var initial_spawn_y: float = 0.0

# Ghost-specific parameters
var float_height: float = 1.5  # Height above ground
var float_bob_timer: float = 0.0
const FLOAT_BOB_SPEED: float = 2.0
const FLOAT_BOB_AMPLITUDE: float = 0.3

# Ambient whisper system
var whisper_timer: float = 0.0
var whisper_interval: float = 8.0

# Glow light reference
var glow_light: OmniLight3D = null

func _ready() -> void:
	enemy_name = "Ghost"
	max_health = 60.0
	health = max_health
	move_speed = 2.5
	charge_speed = 4.5  # Speed up when close to player
	strafe_speed = 2.0
	attack_range = 1.2
	attack_cooldown_time = 1.5
	windup_time = 0.4
	detection_range = 20.0
	preferred_distance = 5.0
	throw_range = 0.0  # Ghosts don't throw
	throw_min_range = 0.0
	weapon_id = "fists"

	loot_table = {"glowing_spore": 1, "fungal_essence": 1}
	rare_loot_table = {"ectoplasm": [1, 0.25]}  # 25% chance

	# Ghost resistances - ethereal undead creature
	damage_resistances = {
		WeaponData.DamageType.SLASH: 0.6,    # 40% resistant (ethereal, blade passes through)
		WeaponData.DamageType.BLUNT: 0.6,    # 40% resistant (ethereal)
		WeaponData.DamageType.PIERCE: 0.5,   # 50% resistant (arrows pass through)
		WeaponData.DamageType.FIRE: 1.5,     # 50% weak to fire (burns away ectoplasm)
		WeaponData.DamageType.ICE: 0.7,      # 30% resistant (already cold)
		WeaponData.DamageType.POISON: 0.3,   # 70% resistant (no body to poison)
	}

	super._ready()

	# Ghosts are moderately aggressive
	aggression = randf_range(0.5, 0.8)
	patience = randf_range(0.2, 0.5)

	# Randomize whisper timing
	whisper_timer = randf_range(2.0, 6.0)
	whisper_interval = randf_range(5.0, 12.0)

	# Randomize float height
	float_height = randf_range(1.0, 2.0)

	print("[Ghost] Ghost ready (network_id=%d)" % network_id)

func _get_death_sound() -> String:
	return "ghost_ambient"

## Override host AI to float above ground and disable gravity
func _run_host_ai(delta: float) -> void:
	# Update cooldowns
	if attack_cooldown > 0:
		attack_cooldown -= delta
	if throw_cooldown > 0:
		throw_cooldown -= delta

	state_timer += delta

	# Capture initial spawn Y on first frame
	if initial_spawn_y == 0.0 and global_position.y > 0.1:
		initial_spawn_y = global_position.y - float_height

	# Float bob animation
	float_bob_timer += delta * FLOAT_BOB_SPEED
	var bob_offset = sin(float_bob_timer) * FLOAT_BOB_AMPLITUDE

	# Maintain float height above terrain (NO gravity - ghosts float!)
	var target_y = initial_spawn_y + float_height + bob_offset
	if abs(global_position.y - target_y) > 0.1:
		velocity.y = (target_y - global_position.y) * 3.0
	else:
		velocity.y = 0.0

	# AI update
	_update_ai(delta)

	# Smooth rotation
	_update_rotation(delta)

	# Ambient whisper sounds
	whisper_timer -= delta
	if whisper_timer <= 0:
		whisper_timer = whisper_interval + randf_range(-2.0, 3.0)
		_play_whisper()

	# Move
	move_and_slide()

## Play ambient whisper sound at ghost's position
func _play_whisper() -> void:
	var players = EnemyAI._get_cached_players(get_tree())
	for p in players:
		if is_instance_valid(p) and global_position.distance_to(p.global_position) < 25.0:
			SoundManager.play_sound_varied("ghost_tongues", global_position, -6.0, 0.2)
			return

## Override body setup - semi-transparent ghostly sphere with glow
func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	body_container.rotation.y = PI
	add_child(body_container)

	# Ghost material - semi-transparent pale blue-white body with PINK glow
	var ghost_mat = StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.8, 0.7, 0.9, 0.4)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.emission_enabled = true
	ghost_mat.emission = Color(0.8, 0.2, 0.6, 1.0)  # PINK glow
	ghost_mat.emission_energy_multiplier = 0.8

	var ghost_inner_mat = StandardMaterial3D.new()
	ghost_inner_mat.albedo_color = Color(0.85, 0.8, 0.95, 0.25)
	ghost_inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_inner_mat.emission_enabled = true
	ghost_inner_mat.emission = Color(1.0, 0.3, 0.7, 1.0)  # Brighter PINK
	ghost_inner_mat.emission_energy_multiplier = 1.2

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.3, 0.7, 0.8)
	eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.0, 0.576, 1.0)  # PINK #ff0093
	eye_mat.emission_energy_multiplier = 2.0

	# Main body (sphere)
	torso = MeshInstance3D.new()
	var body_mesh = SphereMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 0.6
	torso.mesh = body_mesh
	torso.material_override = ghost_mat
	torso.position = Vector3(0, 0.5, 0)
	body_container.add_child(torso)

	# Inner core (smaller, brighter sphere)
	var inner = MeshInstance3D.new()
	var inner_mesh = SphereMesh.new()
	inner_mesh.radius = 0.15
	inner_mesh.height = 0.3
	inner.mesh = inner_mesh
	inner.material_override = ghost_inner_mat
	inner.position = Vector3(0, 0, 0)
	torso.add_child(inner)

	# Head (slightly above body, overlapping)
	head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.2
	head_mesh.height = 0.4
	head.mesh = head_mesh
	head.material_override = ghost_mat
	head.position = Vector3(0, 0.85, 0)
	body_container.add_child(head)

	# Eyes (glowing blue)
	var l_eye_mesh = SphereMesh.new()
	l_eye_mesh.radius = 0.03
	l_eye_mesh.height = 0.06

	var left_eye = MeshInstance3D.new()
	left_eye.mesh = l_eye_mesh
	left_eye.material_override = eye_mat
	left_eye.position = Vector3(-0.08, 0.02, 0.15)
	head.add_child(left_eye)

	var right_eye = MeshInstance3D.new()
	right_eye.mesh = l_eye_mesh
	right_eye.material_override = eye_mat
	right_eye.position = Vector3(0.08, 0.02, 0.15)
	head.add_child(right_eye)

	# Wispy tail (tapers downward)
	var tail = MeshInstance3D.new()
	var tail_mesh = CylinderMesh.new()
	tail_mesh.top_radius = 0.15
	tail_mesh.bottom_radius = 0.02
	tail_mesh.height = 0.4
	tail.mesh = tail_mesh
	tail.material_override = ghost_mat
	tail.position = Vector3(0, 0.15, 0)
	body_container.add_child(tail)

	# OmniLight3D for eerie glow
	glow_light = OmniLight3D.new()
	glow_light.light_color = Color(1.0, 0.3, 0.7)
	glow_light.omni_range = 5.0
	glow_light.light_energy = 0.5
	glow_light.position = Vector3(0, 0.5, 0)
	body_container.add_child(glow_light)

	head_base_height = 0.85

## Override telegraph to use blue-ish warning tint for ghosts
func _set_windup_telegraph(enabled: bool) -> void:
	if not body_container:
		return

	if windup_tween and windup_tween.is_valid():
		windup_tween.kill()

	if enabled:
		# Ghosts brighten before attacking
		if glow_light:
			windup_tween = create_tween()
			windup_tween.tween_property(glow_light, "light_energy", 1.5, 0.25)
	else:
		if glow_light:
			glow_light.light_energy = 0.5
