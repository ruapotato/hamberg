extends Node

## Test script to identify controller button indices
## Add this to a test scene or run from command line

func _ready():
	print("=== Controller Button Test ===")
	print("Press any button to see its index number")
	print("Press Start/Menu to quit")

func _input(event: InputEvent):
	if event is InputEventJoypadButton:
		if event.pressed:
			print("Button pressed: %d (%s)" % [event.button_index, _get_button_name(event.button_index)])

			# Quit on Start button
			if event.button_index == 11:
				get_tree().quit()

	elif event is InputEventJoypadMotion:
		# Only show significant axis movement (ignore drift)
		if abs(event.axis_value) > 0.5:
			print("Axis %d: %.2f" % [event.axis, event.axis_value])

func _get_button_name(index: int) -> String:
	match index:
		0: return "A/Cross"
		1: return "B/Circle"
		2: return "X/Square"
		3: return "Y/Triangle"
		4: return "LB/L1"
		5: return "RB/R1"
		6: return "LT/L2"
		7: return "RT/R2"
		8: return "Back/Select"
		9: return "Start/Menu"
		10: return "L3/Left Stick Click"
		11: return "R3/Right Stick Click"
		12: return "D-Pad Up"
		13: return "D-Pad Down"
		14: return "D-Pad Left"
		15: return "D-Pad Right"
		_: return "Unknown"
