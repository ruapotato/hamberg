extends "res://shared/enemies/enemy.gd"
class_name Boss

## Boss - Base class for boss enemies
##
## Features:
## - Large health bar displayed on screen (not just above head)
## - Phase system for different attack patterns at health thresholds
## - Entrance animation and dramatic spawn
## - Boss music trigger
## - Special guaranteed loot drops
## - Stagger/stun mechanics

signal boss_defeated(boss: Boss)
signal phase_changed(boss: Boss, new_phase: int)
signal boss_spawned(boss: Boss)

# ============================================================================
# BOSS STATS (override in subclasses)
# ============================================================================
@export var boss_name: String = "Boss"
@export var boss_title: String = "The Unnamed"  # e.g., "Guardian of the Valley"
@export var phase_thresholds: Array[float] = [0.66, 0.33]  # Health % to trigger phases
@export var stagger_threshold: float = 0.15  # % of max health damage to cause stagger
@export var stagger_duration: float = 2.0
@export var guaranteed_drops: Array[String] = []  # Item IDs that always drop
@export var boss_scale: float = 2.0  # Size multiplier

# ============================================================================
# BOSS STATE
# ============================================================================
var current_phase: int = 0  # 0 = phase 1, increases at thresholds
var is_staggered: bool = false
var stagger_timer: float = 0.0
var damage_since_last_stagger: float = 0.0
var is_spawning: bool = true  # True during entrance animation
var spawn_timer: float = 0.0
var spawn_duration: float = 3.0  # Time for entrance animation

# Boss health bar UI (created on spawn)
var boss_health_bar: Control = null

# ============================================================================
# BOSS SETUP
# ============================================================================
func _ready() -> void:
	super._ready()

	# Apply boss scale
	if body_container:
		body_container.scale = Vector3.ONE * boss_scale

	# Override some enemy defaults for bosses
	max_health = max_health * 5  # Bosses have much more health
	health = max_health

	# Start with entrance animation
	is_spawning = true
	spawn_timer = 0.0

	# Create boss health bar UI
	_create_boss_health_bar()

	# Emit spawn signal
	boss_spawned.emit(self)

	print("[Boss] %s '%s' spawned! (HP: %.0f, Scale: %.1f)" % [boss_name, boss_title, max_health, boss_scale])

# ============================================================================
# OVERRIDE ENEMY SETUP METHODS (Bosses create their own bodies)
# ============================================================================

## Override: Bosses create their own bodies in subclass, don't use enemy body
func _setup_body() -> void:
	# Don't overwrite body_container if already created by subclass
	if body_container:
		print("[Boss] Skipping _setup_body() - body already created by subclass")
		return
	# If no body yet, call parent (shouldn't happen for properly implemented bosses)
	print("[Boss] WARNING: No body_container found, using default enemy body")
	super._setup_body()

## Override: Bosses have their own attack systems
func _setup_attack_hitbox() -> void:
	# Bosses implement their own attacks (stomp, eye beam, etc.)
	print("[Boss] Skipping _setup_attack_hitbox() - bosses have custom attacks")
	pass

## Override: Setup collision box for boss (larger)
func _setup_collision_box_mesh() -> void:
	# Find the collision shape to match its size
	var collision_shape = get_node_or_null("CollisionShape3D")
	if not collision_shape or not collision_shape.shape:
		return

	var mesh = MeshInstance3D.new()
	mesh.name = "CollisionBoxMesh"

	# Create appropriate mesh based on shape
	if collision_shape.shape is CapsuleShape3D:
		var capsule = CapsuleMesh.new()
		capsule.radius = collision_shape.shape.radius
		capsule.height = collision_shape.shape.height
		mesh.mesh = capsule
	elif collision_shape.shape is BoxShape3D:
		var box = BoxMesh.new()
		box.size = collision_shape.shape.size
		mesh.mesh = box
	elif collision_shape.shape is SphereShape3D:
		var sphere = SphereMesh.new()
		sphere.radius = collision_shape.shape.radius
		mesh.mesh = sphere

	# Blue translucent material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 1.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visible = false  # Hidden by default, toggle with debug

	collision_shape.add_child(mesh)

func _physics_process(delta: float) -> void:
	# Handle entrance animation
	if is_spawning:
		_update_spawn_animation(delta)
		return

	# Handle stagger
	if is_staggered:
		stagger_timer -= delta
		if stagger_timer <= 0:
			is_staggered = false
			print("[Boss] %s recovered from stagger!" % boss_name)
		return

	# Normal processing
	super._physics_process(delta)

# ============================================================================
# SPAWN ANIMATION
# ============================================================================
func _update_spawn_animation(delta: float) -> void:
	spawn_timer += delta

	# Rise from ground or dramatic entrance
	var progress = spawn_timer / spawn_duration
	if body_container:
		# Start below ground and rise up
		var start_y = -2.0 * boss_scale
		var end_y = 0.0
		body_container.position.y = lerp(start_y, end_y, ease(progress, 0.3))

	# Spawn complete
	if spawn_timer >= spawn_duration:
		is_spawning = false
		if body_container:
			body_container.position.y = 0.0
		print("[Boss] %s entrance complete!" % boss_name)
		_on_spawn_complete()

## Override in subclasses for custom spawn effects
func _on_spawn_complete() -> void:
	pass

# ============================================================================
# BOSS HEALTH BAR UI
# ============================================================================
func _create_boss_health_bar() -> void:
	# Create a CanvasLayer for the boss health bar
	var canvas = CanvasLayer.new()
	canvas.name = "BossHealthBarLayer"
	canvas.layer = 10  # Above other UI
	add_child(canvas)

	# Create the health bar container
	boss_health_bar = Control.new()
	boss_health_bar.name = "BossHealthBar"
	boss_health_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	boss_health_bar.custom_minimum_size = Vector2(0, 80)
	canvas.add_child(boss_health_bar)

	# Background panel
	var bg = ColorRect.new()
	bg.name = "Background"  # Named for reliable path lookup
	bg.color = Color(0.1, 0.1, 0.1, 0.8)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.offset_top = 20
	bg.offset_bottom = 70
	bg.offset_left = 100
	bg.offset_right = -100
	boss_health_bar.add_child(bg)

	# Health bar background
	var bar_bg = ColorRect.new()
	bar_bg.name = "BarBackground"
	bar_bg.color = Color(0.3, 0.0, 0.0, 1.0)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.offset_top = 30
	bar_bg.offset_bottom = -10
	bar_bg.offset_left = 10
	bar_bg.offset_right = -10
	bg.add_child(bar_bg)

	# Health bar fill
	var bar_fill = ColorRect.new()
	bar_fill.name = "BarFill"
	bar_fill.color = Color(0.8, 0.1, 0.1, 1.0)
	bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.anchor_right = 1.0
	bar_fill.offset_top = 2
	bar_fill.offset_bottom = -2
	bar_fill.offset_left = 2
	bar_fill.offset_right = -2
	bar_bg.add_child(bar_fill)

	# Boss name label
	var name_label = Label.new()
	name_label.name = "BossName"
	name_label.text = "%s - %s" % [boss_name, boss_title]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_label.offset_top = 5
	name_label.offset_bottom = 28
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	bg.add_child(name_label)

	_update_boss_health_bar()

func _update_boss_health_bar() -> void:
	if not boss_health_bar:
		return

	var bar_fill = boss_health_bar.get_node_or_null("Background/BarBackground/BarFill")
	if bar_fill:
		var health_percent = health / max_health
		bar_fill.anchor_right = health_percent

		# Color changes based on phase
		match current_phase:
			0:
				bar_fill.color = Color(0.8, 0.1, 0.1, 1.0)  # Red
			1:
				bar_fill.color = Color(0.8, 0.5, 0.1, 1.0)  # Orange
			2:
				bar_fill.color = Color(0.8, 0.8, 0.1, 1.0)  # Yellow
			_:
				bar_fill.color = Color(0.8, 0.1, 0.8, 1.0)  # Purple

# ============================================================================
# DAMAGE AND PHASES
# ============================================================================
func take_damage(damage: float, knockback: float = 0.0, direction: Vector3 = Vector3.ZERO, damage_type: int = -1) -> void:
	if is_dead or is_spawning:
		return

	# Track damage for stagger
	damage_since_last_stagger += damage

	# Check for stagger
	if damage_since_last_stagger >= max_health * stagger_threshold:
		_trigger_stagger()
		damage_since_last_stagger = 0.0

	# Apply damage
	super.take_damage(damage, knockback, direction, damage_type)

	# Update boss health bar
	_update_boss_health_bar()

	# Check for phase transitions
	_check_phase_transition()

func _trigger_stagger() -> void:
	if is_staggered:
		return

	is_staggered = true
	stagger_timer = stagger_duration

	# Visual feedback
	if body_container:
		var tween = create_tween()
		tween.tween_property(body_container, "rotation:z", 0.2, 0.1)
		tween.tween_property(body_container, "rotation:z", -0.2, 0.1)
		tween.tween_property(body_container, "rotation:z", 0.0, 0.1)

	print("[Boss] %s STAGGERED! (%.1f seconds)" % [boss_name, stagger_duration])

func _check_phase_transition() -> void:
	var health_percent = health / max_health

	for i in range(phase_thresholds.size()):
		if current_phase <= i and health_percent <= phase_thresholds[i]:
			current_phase = i + 1
			_on_phase_change(current_phase)
			phase_changed.emit(self, current_phase)
			break

## Override in subclasses for phase-specific behavior
func _on_phase_change(new_phase: int) -> void:
	print("[Boss] %s entered PHASE %d!" % [boss_name, new_phase + 1])

	# Default: brief invulnerability and roar
	is_staggered = true
	stagger_timer = 1.0

	# Visual effect
	_set_body_tint(Color(1.5, 0.5, 0.5, 1.0))
	get_tree().create_timer(0.5).timeout.connect(_reset_body_tint)

# ============================================================================
# DEATH AND LOOT
# ============================================================================
func _die() -> void:
	if is_dead:
		return

	is_dead = true
	print("[Boss] %s DEFEATED!" % boss_name)

	# Play death sound
	SoundManager.play_sound("enemy_death", global_position)

	# Remove boss health bar
	if boss_health_bar:
		boss_health_bar.get_parent().queue_free()

	# Emit signals
	died.emit(self)
	boss_defeated.emit(self)

	# Drop guaranteed loot
	if is_host:
		_drop_boss_loot()

	# Death animation - dramatic collapse
	if body_container:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(body_container, "position:y", -1.0 * boss_scale, 2.0)
		tween.tween_property(body_container, "rotation:x", PI / 2, 1.5)
		tween.tween_property(body_container, "scale", Vector3.ONE * boss_scale * 0.5, 2.0)
		tween.chain().tween_callback(queue_free)

func _drop_boss_loot() -> void:
	# Drop guaranteed items
	var loot: Dictionary = {}
	for item_id in guaranteed_drops:
		loot[item_id] = 1

	# Add regular loot table
	for item_id in loot_table:
		if loot.has(item_id):
			loot[item_id] += loot_table[item_id]
		else:
			loot[item_id] = loot_table[item_id]

	if loot.is_empty():
		return

	print("[Boss] Dropping loot: %s" % loot)

	var network_ids: Array = []
	var id_counter: int = 0
	for resource_type in loot:
		var amount: int = loot[resource_type]
		for i in amount:
			var net_id = "%s_%d_%d" % [boss_name, Time.get_ticks_msec(), id_counter]
			id_counter += 1
			network_ids.append(net_id)

	var pos_array = [global_position.x, global_position.y, global_position.z]
	NetworkManager.rpc_request_resource_drops.rpc_id(1, loot, pos_array, network_ids)
