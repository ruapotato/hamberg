extends StaticBody3D

## BuildingPiece - Individual building component (walls, floors, etc.)
## Used by hammer build mode for placement

@export var piece_name: String = "building_piece"
@export var grid_size: Vector3 = Vector3(2.0, 2.0, 0.2)
@export var snap_to_grid: bool = true
@export var can_rotate: bool = false
@export var rotation_angle: float = 26.5651  # Default roof angle

var max_health: float = 100.0
var current_health: float = 100.0
var is_preview: bool = false  # Ghost preview in build mode
var can_place: bool = true  # Whether current position is valid

func _ready() -> void:
	current_health = max_health

	if is_preview:
		_setup_preview_mode()

## Set up as a ghost preview
func _setup_preview_mode() -> void:
	# Make semi-transparent
	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat = mat.duplicate()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.5
				child.set_surface_override_material(0, mat)

	# Disable collision for preview
	collision_layer = 0
	collision_mask = 0

## Update preview color based on placement validity
func set_preview_valid(valid: bool) -> void:
	can_place = valid

	var color_tint = Color.GREEN if valid else Color.RED

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat.albedo_color = color_tint
				mat.albedo_color.a = 0.5

## Take damage (SERVER-SIDE)
func take_damage(damage: float) -> bool:
	current_health -= damage

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

## Called when destroyed
func _on_destroyed() -> void:
	print("[BuildingPiece] %s destroyed!" % piece_name)
	queue_free()
