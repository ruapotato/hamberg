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
var attack_recovery_time: float = 1.5

# Visual components (arms/legs inherited from AnimatedCharacter)
var eye_mesh: MeshInstance3D = null
var eye_light: OmniLight3D = null
var eye_beam_area: Area3D = null

# Attack state
var is_eye_beam_active: bool = false
var beam_sweep_angle: float = 0.0

# Animation state - use continuous time for smooth animation
var anim_time: float = 0.0
var walk_anim_time: float = 0.0
var idle_anim_time: float = 0.0
var breath_scale: float = 1.0

# Body offset to align feet with ground (collision shape compensation)
const BODY_Y_OFFSET: float = 1.5

# Smooth rotation
var target_rotation_y: float = 0.0
var current_rotation_y: float = 0.0
const ROTATION_SPEED: float = 3.0

# Tweens for attack animations
var current_anim_tween: Tween = null

# Threat tracking for smart targeting
var threat_table: Dictionary = {}  # peer_id -> total damage dealt
var last_damage_time: float = 0.0
const THREAT_DECAY_TIME: float = 5.0  # Seconds before threat decays
const RECENT_DAMAGE_WINDOW: float = 3.0  # If damaged within this time, prioritize threat

func _ready() -> void:
	# Set Cyclops-specific stats before super._ready()
	boss_name = "Cyclops"
	boss_title = "Guardian of the Valley"
	enemy_name = "Cyclops"

	# Boss stats
	max_health = 500.0
	boss_scale = 2.5  # Slightly smaller for better proportions
	phase_thresholds = [0.66, 0.33]
	stagger_threshold = 0.10
	stagger_duration = 3.0
	guaranteed_drops = ["cyclops_eye"]

	# Movement - slower but heavy
	move_speed = 3.0
	charge_speed = 4.5
	detection_range = 35.0
	attack_range = 5.0

	# Loot
	loot_table = {"stone": 10, "resin": 5}

	# Build the cyclops body
	_setup_cyclops_body()

	# Call parent ready (this applies scale and creates health bar)
	super._ready()

	cyclops_state = CyclopsState.SPAWNING
	current_rotation_y = rotation.y
	target_rotation_y = rotation.y

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Continuous animation time
	anim_time += delta
	idle_anim_time += delta

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
		_update_stagger_animation(delta)
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
		# Non-host: sync cyclops state from ai_state and update boss health bar
		_sync_cyclops_state_from_ai()
		_sync_boss_health_bar()
		# Non-host: update eye beam if active (spin and damage)
		if cyclops_state == CyclopsState.EYE_BEAM and is_eye_beam_active:
			_update_eye_beam_follower(delta)

	# Smooth rotation (AFTER follower interpolation so it overrides base class rotation)
	_update_smooth_rotation(delta)

	# Always update visuals locally
	_update_eye_glow(delta)
	_update_cyclops_animation(delta)

# ============================================================================
# SMOOTH ROTATION
# ============================================================================
func _update_smooth_rotation(delta: float) -> void:
	# Non-host clients get rotation from sync data
	if not is_host:
		target_rotation_y = sync_rotation_y

	# Smoothly rotate toward target rotation
	var diff = target_rotation_y - current_rotation_y
	# Handle wrap-around
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU

	current_rotation_y += diff * ROTATION_SPEED * delta
	rotation.y = current_rotation_y

func _face_target_smooth() -> void:
	if target_player and is_instance_valid(target_player):
		var dir = target_player.global_position - global_position
		dir.y = 0
		if dir.length() > 0.1:
			target_rotation_y = atan2(dir.x, dir.z)

# ============================================================================
# CYCLOPS AI
# ============================================================================
func _run_cyclops_ai(delta: float) -> void:
	state_timer += delta

	# Re-evaluate target periodically or if none
	if not target_player or not is_instance_valid(target_player):
		target_player = _find_best_target()
		if not target_player:
			cyclops_state = CyclopsState.IDLE
			return
	else:
		# Re-check target every second to potentially switch to higher threat
		if fmod(state_timer, 1.0) < delta:
			var new_target = _find_best_target()
			if new_target and new_target != target_player:
				target_player = new_target

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
	_face_target_smooth()

	var phase_speed_mult = 1.0 + (current_phase * 0.2)

	# Close range: Stomp
	if distance < stomp_radius * 1.5 and stomp_timer <= 0:
		_start_stomp()
		return

	# Medium range: Boulder or Eye Beam (Phase 2+)
	if distance > stomp_radius and distance < detection_range * 0.7:
		if current_phase >= 1 and eye_beam_timer <= 0 and randf() < 0.3:
			_start_eye_beam()
			return
		if boulder_timer <= 0:
			_start_boulder_throw()
			return

	# Move toward target
	if distance > attack_range:
		cyclops_state = CyclopsState.WALKING
		# walk_anim_time is now incremented in _animate_walk() for all clients

		var direction = (target_player.global_position - global_position).normalized()
		direction.y = 0
		velocity.x = direction.x * move_speed * phase_speed_mult
		velocity.z = direction.z * move_speed * phase_speed_mult

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

	# Broadcast to other clients
	if is_host:
		_broadcast_action({"type": "stomp_windup"})

	# Kill any existing animation
	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	# SIDE STOMP - Lean left, raise right leg out to the side, then slam down
	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_IN_OUT)
	current_anim_tween.set_trans(Tween.TRANS_SINE)

	# Phase 1: Shift weight, lean RIGHT toward the stomping side (0.0 - 0.6s)
	if body_container:
		# Lean body to the RIGHT (positive Z rotation)
		current_anim_tween.tween_property(body_container, "rotation:z", 0.35, 0.6)
		# Slight backward lean for balance
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", -0.1, 0.6)

	# Phase 2: Raise right leg OUT TO THE RIGHT SIDE (0.6 - 1.2s)
	if right_leg:
		# Rotate leg outward to the RIGHT (positive Z)
		current_anim_tween.tween_property(right_leg, "rotation:z", 1.0, 0.6)
		# Slight forward angle
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", -0.3, 0.6)
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			# Bend knee slightly
			current_anim_tween.parallel().tween_property(right_knee, "rotation:x", 0.4, 0.6)

	# Lean RIGHT more to wind up for the stomp
	if body_container:
		current_anim_tween.parallel().tween_property(body_container, "rotation:z", 0.5, 0.6)

	# Arms for balance - right arm out, left arm up
	if left_arm:
		current_anim_tween.parallel().tween_property(left_arm, "rotation:x", -0.8, 0.6)
		current_anim_tween.parallel().tween_property(left_arm, "rotation:z", -0.4, 0.6)
	if right_arm:
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.8, 0.6)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:x", -0.3, 0.6)

func _update_stomp_windup(delta: float) -> void:
	_face_target_smooth()
	# Longer windup for dramatic effect (matches the 1.2s animation)
	if state_timer >= 1.3:
		_execute_stomp()

func _execute_stomp() -> void:
	cyclops_state = CyclopsState.STOMPING
	state_timer = 0.0
	print("[Cyclops] STOMP!")

	# Broadcast to other clients
	if is_host:
		_broadcast_action({"type": "stomp", "pos": [global_position.x, global_position.y, global_position.z]})

	# Kill existing animation
	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	# SIDE STOMP SLAM - Leg comes down from side, body shifts right with impact
	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_IN)
	current_anim_tween.set_trans(Tween.TRANS_EXPO)

	# Slam leg down from side position - FAST
	if right_leg:
		# Bring leg back down (Z rotation back to 0)
		current_anim_tween.tween_property(right_leg, "rotation:z", 0.0, 0.12)
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", 0.2, 0.12)
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			current_anim_tween.parallel().tween_property(right_knee, "rotation:x", 0.0, 0.12)

	# Body shifts LEFT with impact (opposite direction of windup lean)
	if body_container:
		# Quick shift to left on impact
		current_anim_tween.parallel().tween_property(body_container, "rotation:z", -0.15, 0.12)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", 0.1, 0.12)

	# After impact, recover to neutral
	if body_container:
		current_anim_tween.tween_property(body_container, "rotation:z", 0.0, 0.5)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", 0.0, 0.5)

	# Reset leg fully
	if right_leg:
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", 0.0, 0.5)

	# Reset arms to neutral
	if left_arm:
		current_anim_tween.parallel().tween_property(left_arm, "rotation:x", 0.0, 0.5)
		current_anim_tween.parallel().tween_property(left_arm, "rotation:z", 0.0, 0.5)
	if right_arm:
		current_anim_tween.parallel().tween_property(right_arm, "rotation:x", 0.0, 0.5)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.0, 0.5)

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
				knockback_dir.y = 0.5
				print("[Cyclops] Stomp hit player! (%.1f damage)" % damage)
				player.take_damage(damage, get_instance_id(), knockback_dir * 12.0, -1)

	# Create shockwave effect
	_create_stomp_effect()

	stomp_timer = stomp_cooldown / (1.0 + current_phase * 0.2)

func _update_stomping(delta: float) -> void:
	if state_timer >= 0.6:
		cyclops_state = CyclopsState.RECOVERING
		state_timer = 0.0

func _create_stomp_effect() -> void:
	# Visual shockwave ring
	var ring = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.3
	ring_mesh.outer_radius = 0.8
	ring.mesh = ring_mesh
	ring.rotation.x = PI / 2

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.6, 0.3, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat

	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.2, 0)

	# Expand and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * stomp_radius * boss_scale * 2.5, 0.4)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)

# ============================================================================
# BOULDER THROW
# ============================================================================
func _start_boulder_throw() -> void:
	cyclops_state = CyclopsState.BOULDER_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] Boulder throw windup!")

	# Broadcast to other clients
	if is_host:
		_broadcast_action({"type": "boulder_windup"})

	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_OUT)
	current_anim_tween.set_trans(Tween.TRANS_BACK)

	# Wind up throwing arm
	if right_arm:
		current_anim_tween.tween_property(right_arm, "rotation:x", -1.8, 0.7)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.3, 0.7)

	# Rotate body back
	if body_container:
		current_anim_tween.parallel().tween_property(body_container, "rotation:y", 0.4, 0.7)

func _update_boulder_windup(delta: float) -> void:
	_face_target_smooth()
	if state_timer >= 0.8:
		_execute_boulder_throw()

func _execute_boulder_throw(target_pos: Vector3 = Vector3.ZERO) -> void:
	cyclops_state = CyclopsState.THROWING_BOULDER
	state_timer = 0.0
	print("[Cyclops] Boulder THROWN!")

	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_OUT)
	current_anim_tween.set_trans(Tween.TRANS_EXPO)

	# Throw motion - fast swing forward
	if right_arm:
		current_anim_tween.tween_property(right_arm, "rotation:x", 0.8, 0.15)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", -0.2, 0.15)
		# Return to rest
		current_anim_tween.tween_property(right_arm, "rotation:x", 0.0, 0.4)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.0, 0.4)

	if body_container:
		current_anim_tween.parallel().tween_property(body_container, "rotation:y", 0.0, 0.3)

	# Determine target position
	var actual_target = target_pos
	if target_pos == Vector3.ZERO and target_player and is_instance_valid(target_player):
		actual_target = target_player.global_position + Vector3(0, 0.5, 0)

	# Broadcast to other clients (with target position)
	if is_host and actual_target != Vector3.ZERO:
		_broadcast_action({"type": "boulder", "target": [actual_target.x, actual_target.y, actual_target.z]})

	# Create boulder projectile
	if actual_target != Vector3.ZERO:
		_spawn_boulder_at_target(actual_target)

	boulder_timer = boulder_cooldown / (1.0 + current_phase * 0.15)

func _spawn_boulder_at_target(target_pos: Vector3) -> void:
	var boulder = Area3D.new()
	boulder.name = "CyclopsBoulder"
	boulder.collision_layer = 0
	boulder.collision_mask = 2

	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.8
	col.shape = shape
	boulder.add_child(col)

	# Rocky boulder mesh
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6
	mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.4, 0.35)
	mesh.material_override = mat
	boulder.add_child(mesh)

	# Spawn at hand position
	var spawn_pos = global_position + Vector3(0, 2.5 * boss_scale, 0)
	if right_arm:
		spawn_pos = right_arm.global_position + Vector3(0, 0.5, -1.0)

	get_tree().current_scene.add_child(boulder)
	boulder.global_position = spawn_pos

	var phase_speed_mult = 1.0 + current_phase * 0.15
	var travel_time = spawn_pos.distance_to(target_pos) / (boulder_speed * phase_speed_mult)
	travel_time = clamp(travel_time, 0.4, 1.5)

	# Animate boulder flight with spin - tween directly to target
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(boulder, "global_position", target_pos, travel_time)
	tween.tween_property(mesh, "rotation:x", TAU * 3, travel_time)  # Spin
	tween.chain().tween_callback(boulder.queue_free)

	# Damage on hit - only apply on host to prevent double damage
	if is_host:
		boulder.body_entered.connect(func(body):
			if body.has_method("take_damage"):
				var phase_damage_mult = 1.0 + (current_phase * 0.25)
				var damage = boulder_damage * phase_damage_mult
				var kb_dir = (body.global_position - boulder.global_position).normalized()
				print("[Cyclops] Boulder hit player! (%.1f damage)" % damage)
				body.take_damage(damage, get_instance_id(), kb_dir * 10.0, -1)
				boulder.queue_free()
		)
	boulder.monitoring = true

func _update_throwing_boulder(delta: float) -> void:
	if state_timer >= 0.4:
		cyclops_state = CyclopsState.RECOVERING
		state_timer = 0.0

# ============================================================================
# EYE BEAM ATTACK (Phase 2+) - Cyclops sits down and spins!
# ============================================================================
func _start_eye_beam() -> void:
	cyclops_state = CyclopsState.EYE_BEAM_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] EYE BEAM charging - sitting down!")

	# Broadcast to other clients
	if is_host:
		_broadcast_action({"type": "eye_beam_windup"})

	# Kill existing animation
	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	# Cyclops sits down to fire the eye beam at player height
	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_IN_OUT)
	current_anim_tween.set_trans(Tween.TRANS_SINE)

	# Crouch down - lower the whole body
	if body_container:
		# Lower body significantly (from BODY_Y_OFFSET to near ground)
		current_anim_tween.tween_property(body_container, "position:y", 0.3, 1.0)
		# Lean FORWARD to aim beam down (model faces +Z, so positive X = lean forward)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", 0.5, 1.0)

	# Bend legs to crouch
	if left_leg:
		current_anim_tween.parallel().tween_property(left_leg, "rotation:x", -0.6, 1.0)
		var left_knee = left_leg.get_node_or_null("LeftKnee")
		if left_knee:
			current_anim_tween.parallel().tween_property(left_knee, "rotation:x", 1.2, 1.0)
	if right_leg:
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", -0.6, 1.0)
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			current_anim_tween.parallel().tween_property(right_knee, "rotation:x", 1.2, 1.0)

	# Arms brace on ground
	if left_arm:
		current_anim_tween.parallel().tween_property(left_arm, "rotation:x", 0.8, 1.0)
		current_anim_tween.parallel().tween_property(left_arm, "rotation:z", -0.4, 1.0)
	if right_arm:
		current_anim_tween.parallel().tween_property(right_arm, "rotation:x", 0.8, 1.0)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.4, 1.0)

	# Eye glows brighter during charge
	if eye_light:
		current_anim_tween.parallel().tween_property(eye_light, "light_energy", 8.0, 1.0)

func _update_eye_beam_windup(delta: float) -> void:
	# Don't turn - stay put while crouching
	if state_timer >= 1.3:
		_execute_eye_beam()

func _execute_eye_beam() -> void:
	cyclops_state = CyclopsState.EYE_BEAM
	state_timer = 0.0
	is_eye_beam_active = true
	# Start from current body facing direction
	beam_sweep_angle = body_container.rotation.y if body_container else 0.0
	print("[Cyclops] EYE BEAM FIRING - SPINNING!")

	# Broadcast to other clients
	if is_host:
		_broadcast_action({"type": "eye_beam", "angle": beam_sweep_angle})

	_create_eye_beam()
	eye_beam_timer = eye_beam_cooldown / (1.0 + current_phase * 0.1)

func _create_eye_beam() -> void:
	if eye_beam_area:
		eye_beam_area.queue_free()

	eye_beam_area = Area3D.new()
	eye_beam_area.name = "EyeBeam"
	eye_beam_area.collision_layer = 0
	eye_beam_area.collision_mask = 2
	eye_beam_area.monitoring = true

	# Long beam collision - taller to catch players even with height variations
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(2.0, 4.0, 18.0)  # Taller box for better coverage
	col.shape = shape
	col.position.z = 9.0  # Positive Z since model faces +Z
	eye_beam_area.add_child(col)

	# Beam visual - glowing cylinder
	var beam_mesh = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.4
	cylinder.bottom_radius = 0.6
	cylinder.height = 18.0
	beam_mesh.mesh = cylinder
	beam_mesh.rotation.x = PI / 2
	beam_mesh.position.z = 9.0  # Positive Z since model faces +Z

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mesh.material_override = mat
	eye_beam_area.add_child(beam_mesh)

	# Core beam (brighter center)
	var core_mesh = MeshInstance3D.new()
	var core_cyl = CylinderMesh.new()
	core_cyl.top_radius = 0.15
	core_cyl.bottom_radius = 0.25
	core_cyl.height = 18.0
	core_mesh.mesh = core_cyl
	core_mesh.rotation.x = PI / 2
	core_mesh.position.z = 9.0  # Positive Z since model faces +Z

	var core_mat = StandardMaterial3D.new()
	core_mat.albedo_color = Color(1.0, 1.0, 0.8, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.95, 0.7)
	core_mat.emission_energy_multiplier = 5.0
	core_mesh.material_override = core_mat
	eye_beam_area.add_child(core_mesh)

	# Add light to beam
	var beam_light = OmniLight3D.new()
	beam_light.light_color = Color(1.0, 0.8, 0.3)
	beam_light.light_energy = 4.0
	beam_light.omni_range = 10.0
	beam_light.position.z = 5.0  # Positive Z since model faces +Z
	eye_beam_area.add_child(beam_light)

	# Position at eye and tilt downward to hit player height
	if eye_mesh:
		eye_mesh.add_child(eye_beam_area)
		eye_beam_area.position = Vector3(0, 0, 0.3)  # Positive Z since model faces +Z
		# Tilt beam DOWN (model faces +Z, so positive X = aim down)
		eye_beam_area.rotation.x = 0.3
	else:
		add_child(eye_beam_area)
		eye_beam_area.position = Vector3(0, 2.5 * boss_scale, 0)
		eye_beam_area.rotation.x = 0.3

	eye_beam_area.body_entered.connect(_on_eye_beam_hit)

func _on_eye_beam_hit(body: Node3D) -> void:
	if body.has_method("take_damage"):
		var phase_damage_mult = 1.0 + (current_phase * 0.3)
		var damage = eye_beam_damage * phase_damage_mult
		print("[Cyclops] Eye beam hit player! (%.1f damage)" % damage)
		body.take_damage(damage, get_instance_id(), Vector3.ZERO, -1)

func _update_eye_beam(delta: float) -> void:
	# SPIN THE WHOLE BODY while firing - full 360 degree sweep!
	var spin_speed = 1.5  # Radians per second (about 1.5 full rotations during 3 second beam)
	beam_sweep_angle += delta * spin_speed

	# Rotate the whole body container to spin in place
	if body_container:
		body_container.rotation.y = beam_sweep_angle

	# Continuous damage tick
	if eye_beam_area and fmod(state_timer, 0.3) < delta:
		var bodies = eye_beam_area.get_overlapping_bodies()
		for body in bodies:
			_on_eye_beam_hit(body)

	var phase_duration_mult = 1.0 + current_phase * 0.15
	if state_timer >= eye_beam_duration * phase_duration_mult:
		_end_eye_beam()

func _end_eye_beam() -> void:
	is_eye_beam_active = false
	cyclops_state = CyclopsState.RECOVERING
	state_timer = 0.0

	if eye_beam_area:
		eye_beam_area.queue_free()
		eye_beam_area = null

	# Kill existing animation
	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	# Stand back up from crouched position
	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_IN_OUT)
	current_anim_tween.set_trans(Tween.TRANS_SINE)

	# Return body to normal height and rotation
	if body_container:
		current_anim_tween.tween_property(body_container, "position:y", BODY_Y_OFFSET, 0.8)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", 0.0, 0.8)
		current_anim_tween.parallel().tween_property(body_container, "rotation:y", 0.0, 0.8)

	# Straighten legs
	if left_leg:
		current_anim_tween.parallel().tween_property(left_leg, "rotation:x", 0.0, 0.8)
		var left_knee = left_leg.get_node_or_null("LeftKnee")
		if left_knee:
			current_anim_tween.parallel().tween_property(left_knee, "rotation:x", 0.0, 0.8)
	if right_leg:
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", 0.0, 0.8)
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			current_anim_tween.parallel().tween_property(right_knee, "rotation:x", 0.0, 0.8)

	# Lower arms
	if left_arm:
		current_anim_tween.parallel().tween_property(left_arm, "rotation:x", 0.0, 0.8)
		current_anim_tween.parallel().tween_property(left_arm, "rotation:z", 0.0, 0.8)
	if right_arm:
		current_anim_tween.parallel().tween_property(right_arm, "rotation:x", 0.0, 0.8)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.0, 0.8)

	# Dim eye
	if eye_light:
		current_anim_tween.parallel().tween_property(eye_light, "light_energy", 2.5, 0.5)

	print("[Cyclops] Eye beam ended - standing up")

# ============================================================================
# RECOVERY STATE
# ============================================================================
func _update_recovering(delta: float) -> void:
	velocity = Vector3.ZERO
	var phase_recovery_mult = 1.0 - (current_phase * 0.1)
	if state_timer >= attack_recovery_time * phase_recovery_mult:
		cyclops_state = CyclopsState.IDLE
		state_timer = 0.0

# ============================================================================
# THREAT-BASED TARGETING
# ============================================================================

## Track damage from player for threat-based targeting
func _on_damaged_by_player(attacker_peer_id: int, damage: float) -> void:
	last_damage_time = Time.get_ticks_msec() / 1000.0

	if threat_table.has(attacker_peer_id):
		threat_table[attacker_peer_id] += damage
	else:
		threat_table[attacker_peer_id] = damage

	print("[Cyclops] Threat updated: peer %d now has %.1f threat" % [attacker_peer_id, threat_table[attacker_peer_id]])

## Find best target based on threat (if recently damaged) or distance (if not)
func _find_best_target() -> CharacterBody3D:
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_damage = current_time - last_damage_time

	# Decay threat over time
	if time_since_damage > THREAT_DECAY_TIME:
		threat_table.clear()

	# Get all players in range
	var players := EnemyAI._get_cached_players(get_tree())
	var valid_targets: Array = []

	for player in players:
		if player == self or player.is_in_group("enemies"):
			continue
		if player is CharacterBody3D:
			var dist = global_position.distance_to(player.global_position)
			if dist <= detection_range:
				valid_targets.append(player)

	if valid_targets.is_empty():
		return null

	# If damaged recently, prioritize highest threat
	if time_since_damage < RECENT_DAMAGE_WINDOW and not threat_table.is_empty():
		var highest_threat_player: CharacterBody3D = null
		var highest_threat: float = 0.0

		for player in valid_targets:
			# Get peer_id from player name (e.g., "Player_12345")
			var peer_id = 0
			if player.name.begins_with("Player_"):
				peer_id = player.name.substr(7).to_int()

			if threat_table.has(peer_id) and threat_table[peer_id] > highest_threat:
				highest_threat = threat_table[peer_id]
				highest_threat_player = player

		if highest_threat_player:
			return highest_threat_player

	# Default: find nearest player
	var nearest: CharacterBody3D = null
	var nearest_dist: float = INF

	for player in valid_targets:
		var dist = global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player

	return nearest

# ============================================================================
# NON-HOST SYNC HELPERS
# ============================================================================

## Sync cyclops_state from ai_state for non-host clients (for animations)
func _sync_cyclops_state_from_ai() -> void:
	# Map Enemy AIState to CyclopsState for basic movement animations
	match sync_ai_state:
		AIState.IDLE:
			if cyclops_state == CyclopsState.WALKING:
				cyclops_state = CyclopsState.IDLE
		AIState.STALKING, AIState.CIRCLING, AIState.CHARGING:
			if cyclops_state == CyclopsState.IDLE:
				cyclops_state = CyclopsState.WALKING
		AIState.RETREATING:
			cyclops_state = CyclopsState.WALKING
	# Attack states are handled by receive_action

## Update boss health bar on non-host clients when sync_health changes
func _sync_boss_health_bar() -> void:
	if health != sync_health:
		health = sync_health
		_update_boss_health_bar()
		# Check for phase transitions
		_check_phase_transition()

# ============================================================================
# NETWORK SYNC - Boss action broadcasting and receiving
# ============================================================================

## Broadcast boss action to other clients via server
func _broadcast_action(action_data: Dictionary) -> void:
	NetworkManager.rpc_report_boss_action.rpc_id(1, network_id, action_data)

## Receive boss action from server (non-host clients)
func receive_action(action_data: Dictionary) -> void:
	var action_type = action_data.get("type", "")

	match action_type:
		"stomp_windup":
			_start_stomp_animation()
		"stomp":
			_execute_stomp_animation()
			# Check if local player is in stomp range
			_check_local_stomp_damage(action_data)
		"boulder_windup":
			_start_boulder_animation()
		"boulder":
			var target = action_data.get("target", [0, 0, 0])
			var target_pos = Vector3(target[0], target[1], target[2])
			_execute_boulder_animation(target_pos)
		"eye_beam_windup":
			_start_eye_beam_animation()
		"eye_beam":
			var angle = action_data.get("angle", 0.0)
			_execute_eye_beam_animation(angle)

## Start stomp animation only (no AI logic)
func _start_stomp_animation() -> void:
	cyclops_state = CyclopsState.STOMP_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] STOMP windup!")

	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_IN_OUT)
	current_anim_tween.set_trans(Tween.TRANS_SINE)

	if body_container:
		current_anim_tween.tween_property(body_container, "rotation:z", 0.35, 0.6)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", -0.1, 0.6)

	if right_leg:
		current_anim_tween.tween_property(right_leg, "rotation:z", 1.0, 0.6)
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", -0.3, 0.6)
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			current_anim_tween.parallel().tween_property(right_knee, "rotation:x", 0.4, 0.6)

	if body_container:
		current_anim_tween.parallel().tween_property(body_container, "rotation:z", 0.5, 0.6)

	if left_arm:
		current_anim_tween.parallel().tween_property(left_arm, "rotation:x", -0.8, 0.6)
		current_anim_tween.parallel().tween_property(left_arm, "rotation:z", -0.4, 0.6)
	if right_arm:
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.8, 0.6)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:x", -0.3, 0.6)

## Execute stomp animation only (no damage on non-host)
func _execute_stomp_animation() -> void:
	cyclops_state = CyclopsState.STOMPING
	state_timer = 0.0
	print("[Cyclops] STOMP!")

	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_IN)
	current_anim_tween.set_trans(Tween.TRANS_EXPO)

	if right_leg:
		current_anim_tween.tween_property(right_leg, "rotation:z", 0.0, 0.12)
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", 0.2, 0.12)
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			current_anim_tween.parallel().tween_property(right_knee, "rotation:x", 0.0, 0.12)

	if body_container:
		current_anim_tween.parallel().tween_property(body_container, "rotation:z", -0.15, 0.12)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", 0.1, 0.12)

	if body_container:
		current_anim_tween.tween_property(body_container, "rotation:z", 0.0, 0.5)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", 0.0, 0.5)

	if right_leg:
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", 0.0, 0.5)

	if left_arm:
		current_anim_tween.parallel().tween_property(left_arm, "rotation:x", 0.0, 0.5)
		current_anim_tween.parallel().tween_property(left_arm, "rotation:z", 0.0, 0.5)
	if right_arm:
		current_anim_tween.parallel().tween_property(right_arm, "rotation:x", 0.0, 0.5)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.0, 0.5)

	SoundManager.play_sound("tree_fall", global_position)
	_create_stomp_effect()

## Check if local player is hit by stomp (non-host clients)
func _check_local_stomp_damage(action_data: Dictionary) -> void:
	var local_player = _get_local_player()
	if not local_player:
		return

	var stomp_pos_arr = action_data.get("pos", [global_position.x, global_position.y, global_position.z])
	var stomp_pos = Vector3(stomp_pos_arr[0], stomp_pos_arr[1], stomp_pos_arr[2])
	var dist = local_player.global_position.distance_to(stomp_pos)

	if dist < stomp_radius * boss_scale:
		var phase_damage_mult = 1.0 + (current_phase * 0.25)
		var damage = stomp_damage * phase_damage_mult
		var knockback_dir = (local_player.global_position - stomp_pos).normalized()
		knockback_dir.y = 0.5
		print("[Cyclops] Stomp hit player! (%.1f damage)" % damage)
		local_player.take_damage(damage, get_instance_id(), knockback_dir * 12.0, -1)

## Start boulder throw animation only
func _start_boulder_animation() -> void:
	cyclops_state = CyclopsState.BOULDER_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] Boulder throw windup!")

	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_OUT)
	current_anim_tween.set_trans(Tween.TRANS_BACK)

	if right_arm:
		current_anim_tween.tween_property(right_arm, "rotation:x", -1.8, 0.7)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.3, 0.7)

	if body_container:
		current_anim_tween.parallel().tween_property(body_container, "rotation:y", 0.4, 0.7)

## Execute boulder throw animation and spawn visual boulder
func _execute_boulder_animation(target_pos: Vector3) -> void:
	cyclops_state = CyclopsState.THROWING_BOULDER
	state_timer = 0.0
	print("[Cyclops] Boulder THROWN!")

	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_OUT)
	current_anim_tween.set_trans(Tween.TRANS_EXPO)

	if right_arm:
		current_anim_tween.tween_property(right_arm, "rotation:x", 0.8, 0.15)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", -0.2, 0.15)
		current_anim_tween.tween_property(right_arm, "rotation:x", 0.0, 0.4)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.0, 0.4)

	if body_container:
		current_anim_tween.parallel().tween_property(body_container, "rotation:y", 0.0, 0.3)

	# Spawn visual boulder (no collision damage on non-host)
	_spawn_boulder_at_target(target_pos)

	# Schedule local damage check when boulder arrives
	var spawn_pos = global_position + Vector3(0, 2.5 * boss_scale, 0)
	var phase_speed_mult = 1.0 + current_phase * 0.15
	var travel_time = spawn_pos.distance_to(target_pos) / (boulder_speed * phase_speed_mult)
	travel_time = clamp(travel_time, 0.4, 1.5)

	# Check for local damage when boulder would arrive
	get_tree().create_timer(travel_time).timeout.connect(func():
		_check_local_boulder_damage(target_pos)
	)

## Check if local player is hit by boulder (non-host clients)
func _check_local_boulder_damage(target_pos: Vector3) -> void:
	var local_player = _get_local_player()
	if not local_player:
		return

	var dist = local_player.global_position.distance_to(target_pos)
	var boulder_hit_radius = 2.0  # Impact radius

	if dist < boulder_hit_radius:
		var phase_damage_mult = 1.0 + (current_phase * 0.25)
		var damage = boulder_damage * phase_damage_mult
		var kb_dir = (local_player.global_position - target_pos).normalized()
		print("[Cyclops] Boulder hit player! (%.1f damage)" % damage)
		local_player.take_damage(damage, get_instance_id(), kb_dir * 10.0, -1)

## Start eye beam animation only
func _start_eye_beam_animation() -> void:
	cyclops_state = CyclopsState.EYE_BEAM_WINDUP
	state_timer = 0.0
	velocity = Vector3.ZERO
	print("[Cyclops] EYE BEAM charging - sitting down!")

	if current_anim_tween and current_anim_tween.is_valid():
		current_anim_tween.kill()

	current_anim_tween = create_tween()
	current_anim_tween.set_ease(Tween.EASE_IN_OUT)
	current_anim_tween.set_trans(Tween.TRANS_SINE)

	if body_container:
		current_anim_tween.tween_property(body_container, "position:y", 0.3, 1.0)
		current_anim_tween.parallel().tween_property(body_container, "rotation:x", 0.5, 1.0)

	if left_leg:
		current_anim_tween.parallel().tween_property(left_leg, "rotation:x", -0.6, 1.0)
		var left_knee = left_leg.get_node_or_null("LeftKnee")
		if left_knee:
			current_anim_tween.parallel().tween_property(left_knee, "rotation:x", 1.2, 1.0)
	if right_leg:
		current_anim_tween.parallel().tween_property(right_leg, "rotation:x", -0.6, 1.0)
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			current_anim_tween.parallel().tween_property(right_knee, "rotation:x", 1.2, 1.0)

	if left_arm:
		current_anim_tween.parallel().tween_property(left_arm, "rotation:x", 0.8, 1.0)
		current_anim_tween.parallel().tween_property(left_arm, "rotation:z", -0.4, 1.0)
	if right_arm:
		current_anim_tween.parallel().tween_property(right_arm, "rotation:x", 0.8, 1.0)
		current_anim_tween.parallel().tween_property(right_arm, "rotation:z", 0.4, 1.0)

	if eye_light:
		current_anim_tween.parallel().tween_property(eye_light, "light_energy", 8.0, 1.0)

## Execute eye beam animation
func _execute_eye_beam_animation(start_angle: float) -> void:
	cyclops_state = CyclopsState.EYE_BEAM
	state_timer = 0.0
	is_eye_beam_active = true
	beam_sweep_angle = start_angle
	print("[Cyclops] EYE BEAM FIRING - SPINNING!")

	_create_eye_beam()

	# Schedule eye beam end for non-host clients
	var phase_duration_mult = 1.0 + current_phase * 0.15
	var beam_duration = eye_beam_duration * phase_duration_mult
	get_tree().create_timer(beam_duration).timeout.connect(func():
		if not is_host:
			_end_eye_beam()
	)

## Update eye beam for non-host clients (spinning and damage)
func _update_eye_beam_follower(delta: float) -> void:
	state_timer += delta

	# Spin the body
	var spin_speed = 1.5
	beam_sweep_angle += delta * spin_speed
	if body_container:
		body_container.rotation.y = beam_sweep_angle

	# Check damage to local player
	if fmod(state_timer, 0.3) < delta:
		_check_local_eye_beam_damage()

## Check if local player is hit by eye beam (non-host clients)
func _check_local_eye_beam_damage() -> void:
	var local_player = _get_local_player()
	if not local_player:
		return

	if not eye_beam_area:
		return

	# Check if local player overlaps with beam
	var bodies = eye_beam_area.get_overlapping_bodies()
	for body in bodies:
		if body == local_player:
			var phase_damage_mult = 1.0 + (current_phase * 0.3)
			var damage = eye_beam_damage * phase_damage_mult
			print("[Cyclops] Eye beam hit player! (%.1f damage)" % damage)
			local_player.take_damage(damage, get_instance_id(), Vector3.ZERO, -1)
			break

## Get local player for damage checks
func _get_local_player() -> CharacterBody3D:
	for player in get_tree().get_nodes_in_group("players"):
		if player is CharacterBody3D and "is_local_player" in player and player.is_local_player:
			return player
	return null

# ============================================================================
# STAGGER ANIMATION
# ============================================================================
func _update_stagger_animation(delta: float) -> void:
	if body_container:
		# Wobbly stagger
		var wobble = sin(anim_time * 8.0) * 0.1 * (stagger_timer / stagger_duration)
		body_container.rotation.z = wobble

# ============================================================================
# PHASE CHANGES
# ============================================================================
func _on_phase_change(new_phase: int) -> void:
	super._on_phase_change(new_phase)

	match new_phase:
		1:
			print("[Cyclops] Phase 2 - Eye beam unlocked!")
			if eye_light:
				eye_light.light_energy = 10.0
				var tween = create_tween()
				tween.tween_property(eye_light, "light_energy", 3.0, 1.0)
		2:
			print("[Cyclops] Phase 3 - ENRAGED!")
			if eye_light:
				eye_light.light_energy = 5.0
				eye_light.light_color = Color(1.0, 0.4, 0.1)
			move_speed *= 1.25
			charge_speed *= 1.25

# ============================================================================
# VISUALS - Detailed Cyclops Body
# ============================================================================
func _setup_cyclops_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	add_child(body_container)
	# Raise body so feet align with collision shape bottom
	# Legs extend to about y=-0.65 local, scaled by boss_scale (2.5) = -1.625
	# Offset body up to compensate
	body_container.position.y = 1.5

	# Color palette
	var skin_color = Color(0.55, 0.5, 0.45)
	var skin_dark = Color(0.4, 0.36, 0.32)
	var skin_light = Color(0.65, 0.6, 0.55)
	var cloth_color = Color(0.35, 0.28, 0.2)
	var leather_color = Color(0.5, 0.38, 0.25)

	# Materials
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = skin_color

	var skin_dark_mat = StandardMaterial3D.new()
	skin_dark_mat.albedo_color = skin_dark

	var cloth_mat = StandardMaterial3D.new()
	cloth_mat.albedo_color = cloth_color

	var leather_mat = StandardMaterial3D.new()
	leather_mat.albedo_color = leather_color

	# ========== LEGS ==========
	left_leg = _create_leg("LeftLeg", Vector3(-0.3, 0.5, 0), skin_mat, skin_dark_mat, cloth_mat)
	body_container.add_child(left_leg)

	right_leg = _create_leg("RightLeg", Vector3(0.3, 0.5, 0), skin_mat, skin_dark_mat, cloth_mat)
	body_container.add_child(right_leg)

	# ========== TORSO ==========
	# Hips
	var hips = MeshInstance3D.new()
	var hips_mesh = CapsuleMesh.new()
	hips_mesh.radius = 0.35
	hips_mesh.height = 0.5
	hips.mesh = hips_mesh
	hips.material_override = cloth_mat
	hips.position = Vector3(0, 0.6, 0)
	hips.rotation.z = PI / 2
	body_container.add_child(hips)

	# Belly
	var belly = MeshInstance3D.new()
	var belly_mesh = SphereMesh.new()
	belly_mesh.radius = 0.45
	belly.mesh = belly_mesh
	belly.material_override = skin_mat
	belly.position = Vector3(0, 1.0, 0.12)
	belly.scale = Vector3(1.0, 0.85, 0.8)
	body_container.add_child(belly)

	# Chest
	var chest = MeshInstance3D.new()
	var chest_mesh = CapsuleMesh.new()
	chest_mesh.radius = 0.42
	chest_mesh.height = 0.8
	chest.mesh = chest_mesh
	chest.material_override = skin_mat
	chest.position = Vector3(0, 1.5, 0)
	body_container.add_child(chest)
	torso = chest

	# Shoulders
	var left_shoulder = MeshInstance3D.new()
	var shoulder_mesh = SphereMesh.new()
	shoulder_mesh.radius = 0.2
	left_shoulder.mesh = shoulder_mesh
	left_shoulder.material_override = skin_mat
	left_shoulder.position = Vector3(-0.5, 1.7, 0)
	body_container.add_child(left_shoulder)

	var right_shoulder = MeshInstance3D.new()
	right_shoulder.mesh = shoulder_mesh
	right_shoulder.material_override = skin_mat
	right_shoulder.position = Vector3(0.5, 1.7, 0)
	body_container.add_child(right_shoulder)

	# Belt
	var belt = MeshInstance3D.new()
	var belt_mesh = CylinderMesh.new()
	belt_mesh.top_radius = 0.4
	belt_mesh.bottom_radius = 0.4
	belt_mesh.height = 0.1
	belt.mesh = belt_mesh
	belt.material_override = leather_mat
	belt.position = Vector3(0, 0.72, 0)
	body_container.add_child(belt)

	# Loincloth
	var loincloth = MeshInstance3D.new()
	var loin_mesh = BoxMesh.new()
	loin_mesh.size = Vector3(0.35, 0.45, 0.06)
	loincloth.mesh = loin_mesh
	loincloth.material_override = cloth_mat
	loincloth.position = Vector3(0, 0.45, 0.2)
	body_container.add_child(loincloth)

	# ========== ARMS ==========
	left_arm = _create_arm("LeftArm", Vector3(-0.6, 1.65, 0), skin_mat, skin_dark_mat, true)
	body_container.add_child(left_arm)

	right_arm = _create_arm("RightArm", Vector3(0.6, 1.65, 0), skin_mat, skin_dark_mat, false)
	body_container.add_child(right_arm)

	# ========== HEAD ==========
	_create_head(skin_mat, skin_dark_mat)

func _create_leg(leg_name: String, pos: Vector3, skin_mat: Material, skin_dark_mat: Material, cloth_mat: Material) -> Node3D:
	var leg = Node3D.new()
	leg.name = leg_name
	leg.position = pos

	# Thigh
	var thigh = MeshInstance3D.new()
	var thigh_mesh = CapsuleMesh.new()
	thigh_mesh.radius = 0.18
	thigh_mesh.height = 0.6
	thigh.mesh = thigh_mesh
	thigh.material_override = skin_mat
	thigh.position = Vector3(0, -0.25, 0)
	leg.add_child(thigh)

	# Knee joint
	var knee = Node3D.new()
	knee.name = leg_name.replace("Leg", "Knee")
	knee.position = Vector3(0, -0.55, 0)
	leg.add_child(knee)

	var kneecap = MeshInstance3D.new()
	var kneecap_mesh = SphereMesh.new()
	kneecap_mesh.radius = 0.12
	kneecap.mesh = kneecap_mesh
	kneecap.material_override = skin_mat
	kneecap.position = Vector3(0, 0, 0.06)
	knee.add_child(kneecap)

	# Shin
	var shin = MeshInstance3D.new()
	var shin_mesh = CapsuleMesh.new()
	shin_mesh.radius = 0.14
	shin_mesh.height = 0.55
	shin.mesh = shin_mesh
	shin.material_override = skin_mat
	shin.position = Vector3(0, -0.3, 0)
	knee.add_child(shin)

	# Foot
	var foot = MeshInstance3D.new()
	var foot_mesh = BoxMesh.new()
	foot_mesh.size = Vector3(0.22, 0.1, 0.35)
	foot.mesh = foot_mesh
	foot.material_override = skin_dark_mat
	foot.position = Vector3(0, -0.6, 0.06)
	knee.add_child(foot)

	return leg

func _create_arm(arm_name: String, pos: Vector3, skin_mat: Material, skin_dark_mat: Material, is_left: bool) -> Node3D:
	var arm = Node3D.new()
	arm.name = arm_name
	arm.position = pos

	var side = -1.0 if is_left else 1.0

	# Upper arm
	var upper = MeshInstance3D.new()
	var upper_mesh = CapsuleMesh.new()
	upper_mesh.radius = 0.14
	upper_mesh.height = 0.55
	upper.mesh = upper_mesh
	upper.material_override = skin_mat
	upper.position = Vector3(side * 0.1, -0.22, 0)
	upper.rotation.z = side * 0.2
	arm.add_child(upper)

	# Elbow
	var elbow = Node3D.new()
	elbow.name = arm_name.replace("Arm", "Elbow")
	elbow.position = Vector3(side * 0.18, -0.45, 0)
	arm.add_child(elbow)

	var elbow_ball = MeshInstance3D.new()
	var elbow_mesh = SphereMesh.new()
	elbow_mesh.radius = 0.1
	elbow_ball.mesh = elbow_mesh
	elbow_ball.material_override = skin_mat
	elbow.add_child(elbow_ball)

	# Forearm
	var forearm = MeshInstance3D.new()
	var forearm_mesh = CapsuleMesh.new()
	forearm_mesh.radius = 0.11
	forearm_mesh.height = 0.5
	forearm.mesh = forearm_mesh
	forearm.material_override = skin_mat
	forearm.position = Vector3(0, -0.28, 0)
	elbow.add_child(forearm)

	# Hand
	var hand = MeshInstance3D.new()
	var hand_mesh = BoxMesh.new()
	hand_mesh.size = Vector3(0.16, 0.12, 0.2)
	hand.mesh = hand_mesh
	hand.material_override = skin_dark_mat
	hand.position = Vector3(0, -0.55, 0)
	elbow.add_child(hand)

	return arm

func _create_head(skin_mat: Material, skin_dark_mat: Material) -> void:
	# Neck
	var neck = MeshInstance3D.new()
	var neck_mesh = CylinderMesh.new()
	neck_mesh.top_radius = 0.15
	neck_mesh.bottom_radius = 0.18
	neck_mesh.height = 0.2
	neck.mesh = neck_mesh
	neck.material_override = skin_mat
	neck.position = Vector3(0, 1.9, 0)
	body_container.add_child(neck)

	# Head
	var head_node = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.38
	head_node.mesh = head_mesh
	head_node.material_override = skin_mat
	head_node.position = Vector3(0, 2.25, 0)
	head_node.scale = Vector3(1.0, 1.1, 0.95)
	body_container.add_child(head_node)
	head = head_node

	# Brow ridge
	var brow = MeshInstance3D.new()
	var brow_mesh = CapsuleMesh.new()
	brow_mesh.radius = 0.1
	brow_mesh.height = 0.45
	brow.mesh = brow_mesh
	brow.material_override = skin_dark_mat
	brow.position = Vector3(0, 0.12, 0.25)
	brow.rotation.z = PI / 2
	head_node.add_child(brow)

	# Eye socket
	var socket = MeshInstance3D.new()
	var socket_mesh = SphereMesh.new()
	socket_mesh.radius = 0.18
	socket.mesh = socket_mesh
	socket.material_override = skin_dark_mat
	socket.position = Vector3(0, 0.0, 0.28)
	head_node.add_child(socket)

	# THE EYE
	eye_mesh = MeshInstance3D.new()
	var eye_sphere = SphereMesh.new()
	eye_sphere.radius = 0.15
	eye_mesh.mesh = eye_sphere

	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.95, 0.6)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.85, 0.4)
	eye_mat.emission_energy_multiplier = 2.5
	eye_mesh.material_override = eye_mat
	eye_mesh.position = Vector3(0, 0.0, 0.32)
	head_node.add_child(eye_mesh)

	# Pupil (vertical slit)
	var pupil = MeshInstance3D.new()
	var pupil_mesh = BoxMesh.new()
	pupil_mesh.size = Vector3(0.025, 0.1, 0.02)
	pupil.mesh = pupil_mesh
	var pupil_mat = StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.05, 0.02, 0.0)
	pupil.material_override = pupil_mat
	pupil.position = Vector3(0, 0, 0.13)
	eye_mesh.add_child(pupil)

	# Eye light
	eye_light = OmniLight3D.new()
	eye_light.name = "EyeLight"
	eye_light.light_color = Color(1.0, 0.9, 0.5)
	eye_light.light_energy = 2.5
	eye_light.omni_range = 12.0
	eye_light.omni_attenuation = 1.2
	eye_mesh.add_child(eye_light)

	# Nose
	var nose = MeshInstance3D.new()
	var nose_mesh = CapsuleMesh.new()
	nose_mesh.radius = 0.06
	nose_mesh.height = 0.15
	nose.mesh = nose_mesh
	nose.material_override = skin_mat
	nose.position = Vector3(0, -0.1, 0.32)
	nose.rotation.x = -0.3
	head_node.add_child(nose)

	# Jaw
	var jaw = MeshInstance3D.new()
	var jaw_mesh = BoxMesh.new()
	jaw_mesh.size = Vector3(0.3, 0.12, 0.2)
	jaw.mesh = jaw_mesh
	jaw.material_override = skin_mat
	jaw.position = Vector3(0, -0.25, 0.08)
	head_node.add_child(jaw)

	# Tusks
	for i in [-1, 1]:
		var tusk = MeshInstance3D.new()
		var tusk_mesh = CylinderMesh.new()
		tusk_mesh.top_radius = 0.015
		tusk_mesh.bottom_radius = 0.035
		tusk_mesh.height = 0.1
		tusk.mesh = tusk_mesh
		var tusk_mat = StandardMaterial3D.new()
		tusk_mat.albedo_color = Color(0.9, 0.88, 0.8)
		tusk.material_override = tusk_mat
		tusk.position = Vector3(i * 0.1, -0.2, 0.18)
		tusk.rotation.x = -0.2
		head_node.add_child(tusk)

	# Ear
	var ear = MeshInstance3D.new()
	var ear_mesh = SphereMesh.new()
	ear_mesh.radius = 0.1
	ear.mesh = ear_mesh
	ear.material_override = skin_mat
	ear.position = Vector3(-0.38, 0.0, 0)
	ear.scale = Vector3(0.35, 0.9, 0.7)
	head_node.add_child(ear)

func _update_eye_glow(delta: float) -> void:
	if not eye_light:
		return

	# Smooth pulsing
	var pulse = sin(anim_time * 2.5) * 0.25 + 1.0
	var base_energy = 2.5 + current_phase * 0.5

	if is_eye_beam_active:
		base_energy = 6.0
	elif cyclops_state == CyclopsState.EYE_BEAM_WINDUP:
		base_energy = lerp(2.5, 8.0, state_timer / 1.3)

	eye_light.light_energy = base_energy * pulse

func _update_cyclops_animation(delta: float) -> void:
	if not body_container:
		return

	match cyclops_state:
		CyclopsState.WALKING:
			_animate_walk(delta)
		CyclopsState.IDLE:
			_animate_idle(delta)
		_:
			# Reset to neutral during attacks (tweens handle animation)
			pass

func _animate_walk(delta: float) -> void:
	# Increment walk_anim_time here so both host and non-host clients animate
	walk_anim_time += delta
	var walk_speed = 3.5  # Slower animation for heavy creature
	var t = walk_anim_time * walk_speed

	# Reduced leg swing to prevent ground clipping (was 0.35)
	var leg_swing = sin(t) * 0.25
	# More knee bend to lift foot when swinging forward
	var knee_bend_base = 0.35

	if left_leg:
		left_leg.rotation.x = leg_swing
		var left_knee = left_leg.get_node_or_null("LeftKnee")
		if left_knee:
			# Bend knee more when leg swings forward to lift the foot
			var forward_amount = max(0.0, leg_swing)  # Only when swinging forward
			left_knee.rotation.x = knee_bend_base * forward_amount * 3.0

	if right_leg:
		right_leg.rotation.x = -leg_swing
		var right_knee = right_leg.get_node_or_null("RightKnee")
		if right_knee:
			# Bend knee more when leg swings forward to lift the foot
			var forward_amount = max(0.0, -leg_swing)  # Only when swinging forward (opposite)
			right_knee.rotation.x = knee_bend_base * forward_amount * 3.0

	# Arm swing (opposite to legs)
	if left_arm:
		left_arm.rotation.x = -leg_swing * 0.4
	if right_arm:
		right_arm.rotation.x = leg_swing * 0.4

	# Body sway and heavier bounce for large creature
	body_container.rotation.z = sin(t) * 0.04
	# Larger bounce to account for boss_scale (add to base offset)
	body_container.position.y = BODY_Y_OFFSET + abs(sin(t * 2)) * 0.08

func _animate_idle(delta: float) -> void:
	# Breathing
	var breath = sin(idle_anim_time * 1.5) * 0.02
	if torso:
		torso.scale.y = 1.0 + breath
		torso.scale.x = 1.0 - breath * 0.5

	# Subtle weight shift
	body_container.rotation.z = sin(idle_anim_time * 0.8) * 0.015
	body_container.position.y = BODY_Y_OFFSET

	# Reset limbs smoothly (including z rotation from side stomp)
	if left_leg:
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 3.0)
		left_leg.rotation.z = lerp(left_leg.rotation.z, 0.0, delta * 3.0)
	if right_leg:
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 3.0)
		right_leg.rotation.z = lerp(right_leg.rotation.z, 0.0, delta * 3.0)
	if left_arm:
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 3.0)
		left_arm.rotation.z = lerp(left_arm.rotation.z, 0.0, delta * 3.0)
	if right_arm:
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 3.0)
		right_arm.rotation.z = lerp(right_arm.rotation.z, 0.0, delta * 3.0)

## Override spawn animation to use body offset
func _update_spawn_animation(delta: float) -> void:
	spawn_timer += delta

	# Rise from ground with body offset
	var progress = spawn_timer / spawn_duration
	if body_container:
		var start_y = -2.0 * boss_scale
		var end_y = BODY_Y_OFFSET  # Use offset instead of 0
		body_container.position.y = lerp(start_y, end_y, ease(progress, 0.3))

	# Spawn complete
	if spawn_timer >= spawn_duration:
		is_spawning = false
		if body_container:
			body_container.position.y = BODY_Y_OFFSET
		print("[Boss] %s entrance complete!" % boss_name)
		_on_spawn_complete()

func _on_spawn_complete() -> void:
	print("[Cyclops] *ROOOAAARRR!*")
	SoundManager.play_sound("enemy_death", global_position)
	cyclops_state = CyclopsState.IDLE
