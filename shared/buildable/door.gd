extends "res://shared/buildable/building_piece.gd"

## Interactive Door - Can be opened/closed by player interaction

var is_open: bool = false
var is_animating: bool = false
var door_panel: Node3D = null
var door_collision: CollisionShape3D = null

# Interaction settings
var is_interactable: bool = true
var interaction_prompt: String = "Open"

# Door geometry
const PIVOT_X := -0.85  # Pivot point X offset
const DOOR_CENTER_OFFSET := 0.85  # Distance from pivot to door center

func _ready() -> void:
	super._ready()
	door_panel = get_node_or_null("DoorPanel")
	door_collision = get_node_or_null("DoorCollision")

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

	var target_rotation = deg_to_rad(90) if is_open else 0.0
	var tween = create_tween()
	tween.set_parallel(true)

	# Animate door panel rotation
	tween.tween_property(door_panel, "rotation:y", target_rotation, 0.3)

	# Animate collision to follow the door
	if door_collision:
		# Calculate collision position as door rotates around pivot
		# When closed: collision at (0, -0.075, 0)
		# When open 90°: collision at (PIVOT_X, -0.075, DOOR_CENTER_OFFSET)
		var target_pos: Vector3
		if is_open:
			target_pos = Vector3(PIVOT_X, -0.075, DOOR_CENTER_OFFSET)
		else:
			target_pos = Vector3(0, -0.075, 0)

		tween.tween_property(door_collision, "position", target_pos, 0.3)
		tween.tween_property(door_collision, "rotation:y", target_rotation, 0.3)

	tween.set_parallel(false)
	tween.tween_callback(func(): is_animating = false)

## Get interaction prompt for UI
func get_interaction_prompt() -> String:
	return interaction_prompt
