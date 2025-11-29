extends "res://shared/buildable/building_piece.gd"

## Interactive Door - Can be opened/closed by player interaction

var is_open: bool = false
var is_animating: bool = false
var door_panel: Node3D = null

# Interaction settings
var is_interactable: bool = true
var interaction_prompt: String = "Open"

func _ready() -> void:
	super._ready()
	door_panel = get_node_or_null("DoorPanel")

## Called when player interacts with the door
func interact() -> void:
	if is_animating:
		return

	is_open = !is_open
	_animate_door()

	# Update interaction prompt
	interaction_prompt = "Close" if is_open else "Open"

func _animate_door() -> void:
	if not door_panel:
		return

	is_animating = true

	var target_rotation = deg_to_rad(90) if is_open else 0
	var tween = create_tween()
	tween.tween_property(door_panel, "rotation:y", target_rotation, 0.3)
	tween.tween_callback(func(): is_animating = false)

## Get interaction prompt for UI
func get_interaction_prompt() -> String:
	return interaction_prompt
