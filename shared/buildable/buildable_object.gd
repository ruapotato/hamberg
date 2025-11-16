extends StaticBody3D

## BuildableObject - Base class for player-constructed buildings
## Handles placement validation, health, and interaction

@export var object_name: String = "buildable"
@export var max_health: float = 100.0
@export var crafting_station_range: float = 20.0  # Range for workbench influence
@export var is_crafting_station: bool = false
@export var station_type: String = ""  # e.g., "workbench"

var current_health: float = 100.0
var is_placed: bool = false
var chunk_position: Vector2i
var object_id: int = -1
var is_preview: bool = false  # Ghost preview in build mode
var can_place: bool = true  # Whether current position is valid

func _ready() -> void:
	current_health = max_health

	if is_preview:
		_setup_preview_mode()

	if is_crafting_station and not station_type.is_empty():
		print("[BuildableObject] %s crafting station ready (range: %.1fm)" % [station_type, crafting_station_range])

## Check if a position is within this crafting station's range
func is_position_in_range(pos: Vector3) -> bool:
	if not is_crafting_station:
		return false

	return global_position.distance_to(pos) <= crafting_station_range

## Take damage (SERVER-SIDE)
func take_damage(damage: float) -> bool:
	current_health -= damage

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

## Called when destroyed
func _on_destroyed() -> void:
	print("[BuildableObject] %s destroyed!" % object_name)
	queue_free()

## Set up as a ghost preview
func _setup_preview_mode() -> void:
	# Make semi-transparent
	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat = mat.duplicate()
			else:
				mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.5
			child.set_surface_override_material(0, mat)

	# Disable collision during preview
	collision_layer = 0
	collision_mask = 0

## Update preview color based on placement validity
func set_preview_valid(valid: bool, is_snapped: bool = false) -> void:
	can_place = valid

	var color_tint: Color
	if not valid:
		color_tint = Color.RED
	elif is_snapped:
		color_tint = Color(0.3, 1.0, 0.3)  # Bright green when snapped
	else:
		color_tint = Color(0.6, 0.8, 0.6)  # Dimmer green for ground placement

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat.albedo_color = color_tint
				mat.albedo_color.a = 0.6 if is_snapped else 0.5  # Slightly more visible when snapped
