extends Node3D

## TreeSprout - A small sapling that can be punched for early-game wood
## No tool requirement - allows players to bootstrap their wood gathering

@export var cull_distance: float = 80.0
@export var fade_in_duration: float = 0.2
@export var fade_in_distance: float = 60.0

@export var max_health: float = 20.0
@export var required_tool_type: String = ""  # Empty = can punch it!

# Resource drops
@export var resource_drops: Dictionary = {"wood": 2}

var chunk_position: Vector2i
var object_type: String = "tree_sprout"
var object_id: int = -1
var is_visible_in_range: bool = true

var current_health: float = 20.0
var is_destroyed: bool = false

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

# Fade-in state
var is_fading_in: bool = false
var fade_timer: float = 0.0
var original_scale: Vector3 = Vector3.ONE
var target_scale: Vector3 = Vector3.ZERO
var initial_distance: float = 0.0
var skip_fade_in: bool = false

# Sprout color (for variety)
var leaf_color: Color = Color(0.3, 0.7, 0.3)

func _ready() -> void:
	current_health = max_health

	# Start fade-in effect
	if fade_in_duration > 0.0 and not skip_fade_in and initial_distance > fade_in_distance:
		if target_scale != Vector3.ZERO:
			original_scale = target_scale
		else:
			original_scale = scale
		scale = Vector3.ZERO
		is_fading_in = true
		fade_timer = 0.0
	else:
		if target_scale != Vector3.ZERO:
			scale = target_scale

func _process(delta: float) -> void:
	if is_fading_in:
		fade_timer += delta
		var progress := minf(fade_timer / fade_in_duration, 1.0)
		var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
		scale = original_scale * eased_progress

		if progress >= 1.0:
			is_fading_in = false
			scale = original_scale

func update_visibility(nearest_distance: float) -> void:
	var should_be_visible := nearest_distance <= cull_distance
	if should_be_visible != is_visible_in_range:
		is_visible_in_range = should_be_visible
		visible = should_be_visible

## Check if a tool type can damage this object
func can_be_damaged_by(tool_type: String) -> bool:
	# Sprouts can be damaged by anything - fists, sticks, axes, anything!
	return true

func get_required_tool_type() -> String:
	return required_tool_type

## Take damage
func take_damage(damage: float, hit_direction: Vector3 = Vector3.ZERO) -> bool:
	if is_destroyed:
		return false

	current_health -= damage
	print("[TreeSprout] Took %.1f damage (%.1f/%.1f HP)" % [damage, current_health, max_health])

	# Create health bar on first damage
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(1.5)

	if health_bar:
		health_bar.update_health(current_health, max_health)

	# Play hit effect - sprouts wobble dramatically
	_play_hit_effect()

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

func _play_hit_effect() -> void:
	SoundManager.play_sound_varied("bush_hit", global_position)

	# Dramatic wobble for small sprout
	var tween := create_tween()
	var original_rot := rotation
	tween.tween_property(self, "rotation:x", original_rot.x + 0.15, 0.04)
	tween.tween_property(self, "rotation:x", original_rot.x - 0.1, 0.04)
	tween.tween_property(self, "rotation:x", original_rot.x + 0.05, 0.04)
	tween.tween_property(self, "rotation:x", original_rot.x, 0.04)

func _on_destroyed() -> void:
	is_destroyed = true
	print("[TreeSprout] Destroyed! Dropping resources: %s" % resource_drops)

	SoundManager.play_sound_varied("wood_break", global_position)

	# Destruction animation
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

## Get resource drops
func get_resource_drops() -> Dictionary:
	return resource_drops.duplicate()

## Set leaf color for variety
func set_leaf_color(color: Color) -> void:
	leaf_color = color
	var leaves = get_node_or_null("Leaves")
	if leaves and leaves is MeshInstance3D:
		var mat = leaves.get_surface_override_material(0)
		if mat and mat is StandardMaterial3D:
			(mat as StandardMaterial3D).albedo_color = color

# Standard environmental object interface
func set_chunk_position(chunk_pos: Vector2i) -> void:
	chunk_position = chunk_pos

func set_object_type(type: String) -> void:
	object_type = type

func set_target_scale(scl: Vector3) -> void:
	target_scale = scl

func set_initial_distance(distance: float) -> void:
	initial_distance = distance

func get_object_type() -> String:
	return object_type

func set_object_id(id: int) -> void:
	object_id = id

func get_object_id() -> int:
	return object_id
