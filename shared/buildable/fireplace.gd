extends "res://shared/buildable/buildable_object.gd"

## Fireplace - A campfire for warmth and cooking
## Can have a cooking station attached on top

var is_lit: bool = true
var has_cooking_station: bool = false
var cooking_station_node: Node3D = null

@onready var fire_light: OmniLight3D = $FireLight
@onready var embers: MeshInstance3D = $Embers
@onready var cooking_attach_point: Marker3D = $CookingAttachPoint

func _ready() -> void:
	super._ready()
	add_to_group("fireplace")
	_update_fire_state()

func _update_fire_state() -> void:
	if fire_light:
		fire_light.visible = is_lit
	if embers:
		embers.visible = is_lit

func set_lit(lit: bool) -> void:
	is_lit = lit
	_update_fire_state()

func get_cooking_attach_position() -> Vector3:
	if cooking_attach_point:
		return cooking_attach_point.global_position
	return global_position + Vector3(0, 0.4, 0)

func attach_cooking_station(station: Node3D) -> void:
	has_cooking_station = true
	cooking_station_node = station

func detach_cooking_station() -> void:
	has_cooking_station = false
	cooking_station_node = null
