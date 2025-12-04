extends "res://shared/enemies/bosses/boss.gd"
class_name Cyclops

## Cyclops - First boss of the game
##
## A massive one-eyed giant that guards the valley.
## Summoned when player purchases the Glowing Medallion from Shnarken.
##
## ATTACKS:
## - Stomp: Ground pound AOE that damages and knocks back players
## - Boulder Throw: Throws massive rocks at range
## - Eye Beam: Sweeping beam attack (Phase 2+)
## - Frenzy: Rapid attacks in Phase 3
##
## PHASES:
## - Phase 1 (100-66%): Stomp and boulder attacks
## - Phase 2 (66-33%): Adds eye beam, faster attacks
## - Phase 3 (33-0%): Enraged, all attacks faster, more damage

# ============================================================================
# CYCLOPS-SPECIFIC AI STATES
# ============================================================================
enum CyclopsState {
	SPAWNING,
	IDLE,
	WALKING,
	STOMP_WINDUP,
	STOMPING,
	BOULDER_WINDUP,
	THROWING_BOULDER,
	EYE_BEAM_WINDUP,
	EYE_BEAM,
	RECOVERING,
	STAGGERED,
	DYING
}

var cyclops_state: CyclopsState = CyclopsState.SPAWNING

# ============================================================================
# CYCLOPS STATS
# ============================================================================
@export var stomp_damage: float = 25.0
@export var stomp_radius: float = 5.0
@export var stomp_cooldown: float = 4.0
@export var boulder_damage: float = 30.0
@export var boulder_speed: float = 20.0
@export var boulder_cooldown: float = 5.0
@export var eye_beam_damage: float = 15.0  # Per tick
@export var eye_beam_duration: float = 3.0
@export var eye_beam_cooldown: float = 8.0

# Timers
var stomp_timer: float = 0.0
var boulder_timer: float = 0.0
var eye_beam_timer: float = 0.0
var state_timer: float = 0.0
var attack_recovery_time: float = 1.5

# Visual components
var eye_mesh: MeshInstance3D = null
var eye_light: OmniLight3D = null
var eye_beam_area: Area3D = null
var left_arm: Node3D = null
var right_arm: Node3D = null
var left_leg: Node3D = null
var right_leg: Node3D = null

# Attack state
var is_eye_beam_active: bool = false
var beam_sweep_angle: float = 0.0

func _ready() -> void:
	# Set Cyclops-specific stats before super._ready()
	boss_name = "Cyclops"
	boss_title = "Guardian of the Valley"
	enemy_name = "Cyclops"

	# Boss stats
	max_health = 500.0
	boss_scale = 3.0
	phase_thresholds = [0.66, 0.33]
	stagger_threshold = 0.10  # 10% of max health to stagger
	stagger_duration = 3.0
	guaranteed_drops = ["cyclops_eye"]

	# Movement
	move_speed = 2.0
	charge_speed = 3.5
	detection_range = 30.0
	attack_range = 4.0

	# Loot
	loot_table = {"stone": 10, "resin": 5}

	# Build the cyclops body
	_setup_cyclops_body()

	# Call parent ready (this applies scale and creates health bar)
	super._ready()

	cyclops_state = CyclopsState.SPAWNING

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Update cooldowns
	stomp_timer = max(0, stomp_timer - delta)
	boulder_timer = max(0, boulder_timer - delta)
	eye_beam_timer = max(0, eye_beam_timer - delta)

	# Handle spawning
	if is_spawning:
		_update_spawn_animation(delta)
		return

	# Handle stagger
	if is_staggered:
		cyclops_state = CyclopsState.STAGGERED
		stagger_timer -= delta
		if stagger_timer <= 0:
			is_staggered = false
			cyclops_state = CyclopsState.IDLE
			print("[Cyclops] Recovered from stagger!")
		return

	# Run cyclops AI
	if is_host:
		_run_cyclops_ai(delta)
		_send_position_report(delta)
	else:
		_run_follower_interpolation(delta)

	# Update eye glow based on state
	_update_eye_glow()

	# Update animations
	_update_cyclops_animation(delta)

# ============================================================================
# CYCLOPS AI
# ============================================================================
func _run_cyclops_ai(delta: float) -> void:
	state_timer += delta

	# Find target if none
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_nearest_player()
		if not target_player:
			cyclops_state = CyclopsState.IDLE
			_update_idle(delta)
			return

	var distance = global_position.distance_to(target_player.global_position)

	# Lost target
	if distance > detection_range:
		target_player = null
		cyclops_state = CyclopsState.IDLE
		return

	# State machine
	match cyclops_state:
		CyclopsState.IDLE, CyclopsState.WALKING:
			_update_combat_ai(delta, distance)
		CyclopsState.STOMP_WINDUP:
			_update_stomp_windup(delta)
		CyclopsState.STOMPING:
			_update_stomping(delta)
		CyclopsState.BOULDER_WINDUP:
			_update_boulder_windup(delta)
		CyclopsState.THROWING_BOULDER:
			_update_throwing_boulder(delta)
		CyclopsState.EYE_BEAM_WINDUP:
			_update_eye_beam_windup(delta)
		CyclopsState.EYE_BEAM:
			_update_eye_beam(delta)
		CyclopsState.RECOVERING:
			_update_recovering(delta)

func _update_combat_ai(delta: float, distance: float) -> void:
	_face_target()

	# Determine which attack to use based on distance and cooldowns
	var phase_speed_mult = 1.0 + (current_phase * 0.2)  # 20% faster per phase

	# Close range: Stomp
	if distance < stomp_radius * 1.2 and stomp_timer <= 0:
		_start_stomp()
		return

	# Medium range: Boulder or Eye Beam (Phase 2+)
	if distance > stomp_radius and distance < detection_range * 0.7:
		# Eye beam available in Phase 2+
		if current_phase >= 1 and eye_beam_timer <= 0 and randf() < 0.4:
			_start_eye_beam()
			return
		# Boulder throw
		if boulder_timer <= 0:
			_start_boulder_throw()
			return

	# Move toward target
	if distance > attack_range:
		cyclops_state = CyclopsState.WALKING
		var direction = (target_player.global_position - global_position).normalized()
		direction.y = 0
		velocity.x = direction.x * move_speed * phase_speed_mult
		velocity.z = direction.z * move_speed * phase_speed_mult

		# Apply gravity
		if not is_on_floor():
			velocity.y -= gravity * delta

		move_and_slide()
	else:
		cyclops_state = CyclopsState.IDLE
		velocity = Vector3.ZERO

# ============================================================================
# STOMP ATTACK
# ============================================================================
func _start_stomp() -> void:
	cyclops_state = CyclopsState.STOMP_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] STOMP windup!")

	# Raise foot
	if right_leg:
		var tween = create_tween()
		tween.tween_property(right_leg, "position:y", 1.0, 0.5)

func _update_stomp_windup(delta: float) -> void:
	if state_timer >= 0.8:
		_execute_stomp()

func _execute_stomp() -> void:
	cyclops_state = CyclopsState.STOMPING
	state_timer = 0.0
	print("[Cyclops] STOMP!")

	# Slam foot down
	if right_leg:
		var tween = create_tween()
		tween.tween_property(right_leg, "position:y", 0.0, 0.1)

	# Play sound
	SoundManager.play_sound("tree_fall", global_position)

	# Damage players in radius
	var stomp_pos = global_position
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player is CharacterBody3D and player.has_method("take_damage"):
			var dist = player.global_position.distance_to(stomp_pos)
			if dist < stomp_radius * boss_scale:
				var phase_damage_mult = 1.0 + (current_phase * 0.25)
				var damage = stomp_damage * phase_damage_mult
				var knockback_dir = (player.global_position - stomp_pos).normalized()
				knockback_dir.y = 0.3  # Add upward knockback
				print("[Cyclops] Stomp hit player! (%.1f damage)" % damage)
				player.take_damage(damage, get_instance_id(), knockback_dir * 10.0, -1)

	# Create shockwave effect
	_create_stomp_effect()

	stomp_timer = stomp_cooldown / (1.0 + current_phase * 0.2)

func _update_stomping(delta: float) -> void:
	if state_timer >= 0.5:
		cyclops_state = CyclopsState.RECOVERING
		state_timer = 0.0

func _create_stomp_effect() -> void:
	# Visual shockwave ring
	var ring = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 1.0
	ring.mesh = ring_mesh
	ring.rotation.x = PI / 2

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 0.2, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat

	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.1, 0)

	# Expand and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * stomp_radius * boss_scale * 2, 0.5)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.chain().tween_callback(ring.queue_free)

# ============================================================================
# BOULDER THROW
# ============================================================================
func _start_boulder_throw() -> void:
	cyclops_state = CyclopsState.BOULDER_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] Boulder throw windup!")

	# Raise arm
	if right_arm:
		var tween = create_tween()
		tween.tween_property(right_arm, "rotation:x", -1.5, 0.5)

func _update_boulder_windup(delta: float) -> void:
	_face_target()
	if state_timer >= 1.0:
		_execute_boulder_throw()

func _execute_boulder_throw() -> void:
	cyclops_state = CyclopsState.THROWING_BOULDER
	state_timer = 0.0
	print("[Cyclops] Boulder THROWN!")

	# Swing arm forward
	if right_arm:
		var tween = create_tween()
		tween.tween_property(right_arm, "rotation:x", 0.5, 0.15)
		tween.tween_property(right_arm, "rotation:x", 0.0, 0.3)

	# Create boulder projectile
	if target_player:
		_spawn_boulder()

	boulder_timer = boulder_cooldown / (1.0 + current_phase * 0.15)

func _spawn_boulder() -> void:
	var boulder = Area3D.new()
	boulder.name = "CyclopsBoulder"
	boulder.collision_layer = 0
	boulder.collision_mask = 2  # Players

	# Collision
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 1.0 * boss_scale * 0.5
	col.shape = shape
	boulder.add_child(col)

	# Mesh
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = shape.radius
	sphere.height = shape.radius * 2
	mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.3)
	mesh.material_override = mat
	boulder.add_child(mesh)

	# Position at hand
	var spawn_pos = global_position + Vector3(0, 3.0 * boss_scale, 0)
	if right_arm:
		spawn_pos = right_arm.global_position + Vector3(0, 1.0, 0)

	get_tree().current_scene.add_child(boulder)
	boulder.global_position = spawn_pos

	# Calculate trajectory
	var target_pos = target_player.global_position + Vector3(0, 1.0, 0)
	var direction = (target_pos - spawn_pos).normalized()

	# Add arc
	direction.y += 0.2
	direction = direction.normalized()

	# Animate boulder
	var phase_speed_mult = 1.0 + current_phase * 0.1
	var tween = create_tween()
	var travel_time = spawn_pos.distance_to(target_pos) / (boulder_speed * phase_speed_mult)
	travel_time = clamp(travel_time, 0.5, 2.0)

	var end_pos = spawn_pos + direction * boulder_speed * phase_speed_mult * travel_time
	tween.tween_property(boulder, "global_position", end_pos, travel_time)
	tween.tween_callback(boulder.queue_free)

	# Damage on hit
	boulder.body_entered.connect(func(body):
		if body.has_method("take_damage"):
			var phase_damage_mult = 1.0 + (current_phase * 0.25)
			var damage = boulder_damage * phase_damage_mult
			var kb_dir = (body.global_position - boulder.global_position).normalized()
			print("[Cyclops] Boulder hit player! (%.1f damage)" % damage)
			body.take_damage(damage, get_instance_id(), kb_dir * 8.0, -1)
			boulder.queue_free()
	)
	boulder.monitoring = true

func _update_throwing_boulder(delta: float) -> void:
	if state_timer >= 0.3:
		cyclops_state = CyclopsState.RECOVERING
		state_timer = 0.0

# ============================================================================
# EYE BEAM ATTACK (Phase 2+)
# ============================================================================
func _start_eye_beam() -> void:
	cyclops_state = CyclopsState.EYE_BEAM_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] EYE BEAM charging!")

	# Eye glows brighter
	if eye_light:
		var tween = create_tween()
		tween.tween_property(eye_light, "light_energy", 5.0, 1.0)

func _update_eye_beam_windup(delta: float) -> void:
	_face_target()
	if state_timer >= 1.5:
		_execute_eye_beam()

func _execute_eye_beam() -> void:
	cyclops_state = CyclopsState.EYE_BEAM
	state_timer = 0.0
	is_eye_beam_active = true
	beam_sweep_angle = -0.5  # Start sweep from left
	print("[Cyclops] EYE BEAM FIRING!")

	# Create beam visual
	_create_eye_beam()

	eye_beam_timer = eye_beam_cooldown / (1.0 + current_phase * 0.1)

func _create_eye_beam() -> void:
	if eye_beam_area:
		eye_beam_area.queue_free()

	eye_beam_area = Area3D.new()
	eye_beam_area.name = "EyeBeam"
	eye_beam_area.collision_layer = 0
	eye_beam_area.collision_mask = 2  # Players
	eye_beam_area.monitoring = true

	# Long beam collision
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 15.0)  # Long beam
	col.shape = shape
	col.position.z = -7.5  # Extend forward
	eye_beam_area.add_child(col)

	# Beam visual
	var beam_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = shape.size
	beam_mesh.mesh = box
	beam_mesh.position = col.position

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mesh.material_override = mat
	eye_beam_area.add_child(beam_mesh)

	# Add light to beam
	var beam_light = OmniLight3D.new()
	beam_light.light_color = Color(1.0, 0.7, 0.2)
	beam_light.light_energy = 3.0
	beam_light.omni_range = 8.0
	beam_light.position = col.position
	eye_beam_area.add_child(beam_light)

	# Position at eye
	if eye_mesh:
		eye_mesh.add_child(eye_beam_area)
		eye_beam_area.position = Vector3(0, 0, -0.5)
	else:
		add_child(eye_beam_area)
		eye_beam_area.position = Vector3(0, 2.5 * boss_scale, 0)

	# Connect damage
	eye_beam_area.body_entered.connect(_on_eye_beam_hit)

func _on_eye_beam_hit(body: Node3D) -> void:
	if body.has_method("take_damage"):
		var phase_damage_mult = 1.0 + (current_phase * 0.3)
		var damage = eye_beam_damage * phase_damage_mult
		print("[Cyclops] Eye beam hit player! (%.1f damage)" % damage)
		body.take_damage(damage, get_instance_id(), Vector3.ZERO, -1)

func _update_eye_beam(delta: float) -> void:
	# Sweep the beam
	beam_sweep_angle += delta * 0.8  # Sweep speed

	if eye_beam_area:
		eye_beam_area.rotation.y = beam_sweep_angle

	# Check for continuous damage (every 0.5 seconds)
	if eye_beam_area and fmod(state_timer, 0.5) < delta:
		var bodies = eye_beam_area.get_overlapping_bodies()
		for body in bodies:
			_on_eye_beam_hit(body)

	# End beam
	var phase_duration_mult = 1.0 + current_phase * 0.2
	if state_timer >= eye_beam_duration * phase_duration_mult:
		_end_eye_beam()

func _end_eye_beam() -> void:
	is_eye_beam_active = false
	cyclops_state = CyclopsState.RECOVERING
	state_timer = 0.0

	if eye_beam_area:
		eye_beam_area.queue_free()
		eye_beam_area = null

	# Return eye to normal glow
	if eye_light:
		var tween = create_tween()
		tween.tween_property(eye_light, "light_energy", 2.0, 0.5)

	print("[Cyclops] Eye beam ended")

# ============================================================================
# RECOVERY STATE
# ============================================================================
func _update_recovering(delta: float) -> void:
	velocity = Vector3.ZERO
	var phase_recovery_mult = 1.0 - (current_phase * 0.15)  # Faster recovery in later phases
	if state_timer >= attack_recovery_time * phase_recovery_mult:
		cyclops_state = CyclopsState.IDLE
		state_timer = 0.0

# ============================================================================
# PHASE CHANGES
# ============================================================================
func _on_phase_change(new_phase: int) -> void:
	super._on_phase_change(new_phase)

	match new_phase:
		1:
			print("[Cyclops] Phase 2 - Eye beam unlocked!")
			# Flash eye
			if eye_light:
				eye_light.light_energy = 8.0
				var tween = create_tween()
				tween.tween_property(eye_light, "light_energy", 2.5, 1.0)
		2:
			print("[Cyclops] Phase 3 - ENRAGED!")
			# Permanent brighter eye
			if eye_light:
				eye_light.light_energy = 4.0
				eye_light.light_color = Color(1.0, 0.3, 0.1)  # More red
			# Speed boost
			move_speed *= 1.3
			charge_speed *= 1.3

# ============================================================================
# VISUALS
# ============================================================================
func _setup_cyclops_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	add_child(body_container)

	var skin_color = Color(0.5, 0.45, 0.4)  # Gray-brown
	var cloth_color = Color(0.3, 0.25, 0.2)  # Dark brown

	# Materials
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = skin_color

	var cloth_mat = StandardMaterial3D.new()
	cloth_mat.albedo_color = cloth_color

	# === TORSO ===
	var torso = MeshInstance3D.new()
	var torso_mesh = CapsuleMesh.new()
	torso_mesh.radius = 0.5
	torso_mesh.height = 1.5
	torso.mesh = torso_mesh
	torso.material_override = skin_mat
	torso.position = Vector3(0, 1.2, 0)
	body_container.add_child(torso)

	# === HEAD ===
	var head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.5
	head.mesh = head_mesh
	head.material_override = skin_mat
	head.position = Vector3(0, 2.2, 0)
	body_container.add_child(head)
	self.head = head

	# === THE EYE (the defining feature!) ===
	eye_mesh = MeshInstance3D.new()
	var eye_sphere = SphereMesh.new()
	eye_sphere.radius = 0.25
	eye_mesh.mesh = eye_sphere

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.9, 0.3)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.8, 0.2)
	eye_mat.emission_energy_multiplier = 1.5
	eye_mesh.material_override = eye_mat
	eye_mesh.position = Vector3(0, 0.05, 0.35)
	head.add_child(eye_mesh)

	# Pupil
	var pupil = MeshInstance3D.new()
	var pupil_mesh = SphereMesh.new()
	pupil_mesh.radius = 0.08
	pupil.mesh = pupil_mesh
	var pupil_mat = StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.1, 0.05, 0.0)
	pupil.material_override = pupil_mat
	pupil.position = Vector3(0, 0, 0.18)
	eye_mesh.add_child(pupil)

	# Eye light
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color(1.0, 0.85, 0.4)
	eye_light.light_energy = 2.0
	eye_light.omni_range = 10.0
	eye_mesh.add_child(eye_light)

	# === ARMS ===
	var arm_mesh = CapsuleMesh.new()
	arm_mesh.radius = 0.2
	arm_mesh.height = 1.0

	# Left arm
	left_arm = Node3D.new()
	left_arm.name = "LeftArm"
	left_arm.position = Vector3(-0.7, 1.6, 0)
	body_container.add_child(left_arm)

	var left_upper = MeshInstance3D.new()
	left_upper.mesh = arm_mesh
	left_upper.material_override = skin_mat
	left_upper.position = Vector3(0, -0.5, 0)
	left_arm.add_child(left_upper)

	# Right arm
	right_arm = Node3D.new()
	right_arm.name = "RightArm"
	right_arm.position = Vector3(0.7, 1.6, 0)
	body_container.add_child(right_arm)

	var right_upper = MeshInstance3D.new()
	right_upper.mesh = arm_mesh
	right_upper.material_override = skin_mat
	right_upper.position = Vector3(0, -0.5, 0)
	right_arm.add_child(right_upper)

	# === LEGS ===
	var leg_mesh = CapsuleMesh.new()
	leg_mesh.radius = 0.25
	leg_mesh.height = 1.2

	# Left leg
	left_leg = Node3D.new()
	left_leg.name = "LeftLeg"
	left_leg.position = Vector3(-0.3, 0.5, 0)
	body_container.add_child(left_leg)

	var left_thigh = MeshInstance3D.new()
	left_thigh.mesh = leg_mesh
	left_thigh.material_override = cloth_mat
	left_thigh.position = Vector3(0, -0.4, 0)
	left_leg.add_child(left_thigh)

	# Right leg
	right_leg = Node3D.new()
	right_leg.name = "RightLeg"
	right_leg.position = Vector3(0.3, 0.5, 0)
	body_container.add_child(right_leg)

	var right_thigh = MeshInstance3D.new()
	right_thigh.mesh = leg_mesh
	right_thigh.material_override = cloth_mat
	right_thigh.position = Vector3(0, -0.4, 0)
	right_leg.add_child(right_thigh)

	# === LOINCLOTH ===
	var loincloth = MeshInstance3D.new()
	var loin_mesh = BoxMesh.new()
	loin_mesh.size = Vector3(0.8, 0.4, 0.3)
	loincloth.mesh = loin_mesh
	loincloth.material_override = cloth_mat
	loincloth.position = Vector3(0, 0.5, 0)
	body_container.add_child(loincloth)

func _update_eye_glow() -> void:
	if not eye_light:
		return

	# Pulse the eye glow
	var pulse = sin(Time.get_ticks_msec() * 0.003) * 0.3 + 1.0
	var base_energy = 2.0 + current_phase * 0.5

	if is_eye_beam_active:
		base_energy = 5.0
	elif cyclops_state == CyclopsState.EYE_BEAM_WINDUP:
		base_energy = lerp(2.0, 5.0, state_timer / 1.5)

	eye_light.light_energy = base_energy * pulse

func _update_cyclops_animation(delta: float) -> void:
	if not body_container:
		return

	# Walking animation
	if cyclops_state == CyclopsState.WALKING:
		var walk_cycle = sin(Time.get_ticks_msec() * 0.005) * 0.3
		if left_leg:
			left_leg.rotation.x = walk_cycle
		if right_leg:
			right_leg.rotation.x = -walk_cycle
		if left_arm:
			left_arm.rotation.x = -walk_cycle * 0.5
		if right_arm and cyclops_state != CyclopsState.BOULDER_WINDUP:
			right_arm.rotation.x = walk_cycle * 0.5

		# Body sway
		body_container.rotation.z = sin(Time.get_ticks_msec() * 0.003) * 0.05

func _on_spawn_complete() -> void:
	# Roar!
	print("[Cyclops] *ROOOAAARRR!*")
	SoundManager.play_sound("enemy_death", global_position)  # Placeholder for roar

	# Screen shake would go here
	cyclops_state = CyclopsState.IDLE
