extends Control

signal resume_pressed
signal save_pressed
signal quit_pressed

@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var quit_button: Button = $Panel/VBox/QuitButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

var selected_index: int = 0  # For controller D-pad navigation
var buttons: Array[Button] = []

func _ready() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	save_button.pressed.connect(_on_save_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Build button array for D-pad navigation
	buttons = [resume_button, save_button, quit_button]

func _process(_delta: float) -> void:
	if not visible:
		return

	# Close menu with B button (jump)
	# Note: Don't check for ui_cancel or toggle_pause here - let client.gd handle toggle
	# to avoid immediate close in the same frame as opening
	if Input.is_action_just_pressed("jump"):
		hide_menu()
		return

	# D-pad navigation
	if Input.is_action_just_pressed("hotbar_unequip"):  # D-pad Down
		_move_selection(1)
	elif Input.is_action_just_pressed("hotbar_equip"):  # D-pad Up
		_move_selection(-1)

	# A button to activate selected option
	if Input.is_action_just_pressed("interact"):
		_activate_selected()

func _on_resume_pressed() -> void:
	hide_menu()
	resume_pressed.emit()

func _on_save_pressed() -> void:
	status_label.text = "Game saved!"
	status_label.modulate = Color.GREEN
	save_pressed.emit()

	# Clear status after 2 seconds
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(status_label):
		status_label.text = ""

func _on_quit_pressed() -> void:
	quit_pressed.emit()

func show_menu() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	selected_index = 0
	_update_selection_visual()

func hide_menu() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Move selection up/down (controller D-pad)
func _move_selection(direction: int) -> void:
	if buttons.is_empty():
		return

	selected_index += direction

	# Wrap around
	if selected_index < 0:
		selected_index = buttons.size() - 1
	elif selected_index >= buttons.size():
		selected_index = 0

	_update_selection_visual()

## Update visual highlight for selected button
func _update_selection_visual() -> void:
	for i in buttons.size():
		if i == selected_index:
			buttons[i].modulate = Color(1.5, 1.5, 1.0)  # Highlight selected
			buttons[i].grab_focus()
		else:
			buttons[i].modulate = Color.WHITE  # Normal

## Activate the currently selected button (controller A button)
func _activate_selected() -> void:
	if selected_index >= 0 and selected_index < buttons.size():
		buttons[selected_index].pressed.emit()
