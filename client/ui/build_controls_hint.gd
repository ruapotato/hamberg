extends Control

## BuildControlsHint - Shows contextual build controls based on input device
## Automatically switches between keyboard and controller prompts

@onready var controls_label: Label = $Panel/Label

var is_using_controller: bool = false

func _ready() -> void:
	# Connect to input device manager
	var input_manager = get_node_or_null("/root/InputDeviceManager")
	if input_manager:
		input_manager.input_device_changed.connect(_on_input_device_changed)
		is_using_controller = input_manager.using_controller()

	_update_controls_text()
	visible = false  # Start hidden, shown when build mode activates

func _on_input_device_changed(using_controller: bool) -> void:
	is_using_controller = using_controller
	_update_controls_text()

func _update_controls_text() -> void:
	if not controls_label:
		return

	if is_using_controller:
		controls_label.text = """[RT] Place  [Y] Remove
[D-pad] Rotate  [LT] Free
[X] Menu"""
	else:
		controls_label.text = """[LMB] Place  [MMB] Remove
[R/Q] Rotate  [Shift] Free
[RMB] Menu"""

func show_hint() -> void:
	visible = true

func hide_hint() -> void:
	visible = false
