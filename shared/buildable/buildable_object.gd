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

func _ready() -> void:
	current_health = max_health

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
