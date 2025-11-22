extends Node

## InputDeviceManager - Tracks which input device the player is using
## Automatically detects controller vs keyboard/mouse and adjusts UI accordingly

signal input_device_changed(is_using_controller: bool)

enum InputDevice {
	KEYBOARD_MOUSE,
	GAMEPAD
}

var current_device: InputDevice = InputDevice.KEYBOARD_MOUSE
var is_using_controller: bool = false

func _ready() -> void:
	# Check if any gamepads are connected at startup
	var connected_gamepads = Input.get_connected_joypads()
	if connected_gamepads.size() > 0:
		print("[InputDeviceManager] Gamepad detected at startup: %s" % Input.get_joy_name(connected_gamepads[0]))
		# Don't auto-switch to controller at startup - wait for input
	else:
		print("[InputDeviceManager] No gamepad detected at startup")

func _input(event: InputEvent) -> void:
	var previous_device = current_device

	# Detect gamepad input
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Filter out very small joystick drift
		if event is InputEventJoypadMotion:
			if abs(event.axis_value) < 0.3:  # Deadzone for device detection
				return

		current_device = InputDevice.GAMEPAD
		is_using_controller = true

	# Detect keyboard/mouse input
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		# Ignore mouse motion if controller is being used (prevents accidental switches)
		if event is InputEventMouseMotion and current_device == InputDevice.GAMEPAD:
			return

		current_device = InputDevice.KEYBOARD_MOUSE
		is_using_controller = false

	# Notify if device changed
	if previous_device != current_device:
		print("[InputDeviceManager] Input device changed to: %s" % ("Gamepad" if is_using_controller else "Keyboard/Mouse"))
		input_device_changed.emit(is_using_controller)

## Get the current input device
func get_current_device() -> InputDevice:
	return current_device

## Check if player is using a controller
func using_controller() -> bool:
	return is_using_controller

## Get appropriate button prompt icon/text based on current device
func get_button_prompt(action: String) -> String:
	if is_using_controller:
		# Return controller button names (Valheim-style layout)
		match action:
			"jump": return "A"
			"attack": return "Y/RT"
			"block": return "LT"
			"special_attack": return "RB"
			"interact": return "X"
			"toggle_inventory": return "Menu"
			"sprint": return "LB"
			"open_build_menu": return "B"
			"toggle_map": return "View"
			"build_next_piece": return "RB"
			"build_prev_piece": return "LB"
			_: return "?"
	else:
		# Return keyboard/mouse button names
		match action:
			"jump": return "Space"
			"attack": return "Left Click"
			"block": return "Right Click"
			"special_attack": return "Middle Click"
			"interact": return "E"
			"toggle_inventory": return "Tab"
			"sprint": return "Shift"
			"open_build_menu": return "Q"
			"toggle_map": return "M"
			_: return "?"
