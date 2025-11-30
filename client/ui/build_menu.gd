extends Control

## BuildMenu - Shows available building pieces when hammer is equipped
## Opens with right-click, closes when piece is selected

signal piece_selected(piece_name: String)
signal menu_closed()

var available_pieces: Array = [
	"workbench",
	"fireplace",
	"cooking_station",
	"chest",
	"wooden_wall",
	"wooden_floor",
	"wooden_door",
	"wooden_beam",
	"wooden_roof_26",
	"wooden_roof_45",
	"wooden_stairs"
]

var is_open: bool = false
var selected_index: int = 0  # For controller D-pad navigation

@onready var panel: Panel = $Panel
@onready var piece_list: VBoxContainer = $Panel/PieceList

func _ready() -> void:
	_populate_piece_list()
	hide_menu()

func _populate_piece_list() -> void:
	if not piece_list:
		print("[BuildMenu] ERROR: piece_list is null!")
		return

	# Clear existing buttons
	for child in piece_list.get_children():
		child.queue_free()

	# Create button for each piece
	for piece_name in available_pieces:
		var button = Button.new()
		button.custom_minimum_size = Vector2(200, 40)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT

		# Format display name
		var display_name = piece_name.replace("_", " ").capitalize()
		button.text = display_name

		# Connect button
		button.pressed.connect(_on_piece_button_pressed.bind(piece_name))

		piece_list.add_child(button)

	print("[BuildMenu] Created %d buttons" % piece_list.get_child_count())

func _on_piece_button_pressed(piece_name: String) -> void:
	print("[BuildMenu] Selected piece: %s" % piece_name)
	piece_selected.emit(piece_name)
	hide_menu()

## Show the build menu
func show_menu() -> void:
	if is_open:
		return

	is_open = true
	visible = true
	selected_index = 0
	_update_selection_visual()

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("[BuildMenu] Opened - Select a building piece")
	print("[BuildMenu] Debug - visible: %s, position: %s, size: %s" % [visible, position, size])
	if panel:
		print("[BuildMenu] Debug - panel visible: %s, position: %s, size: %s" % [panel.visible, panel.position, panel.size])

## Hide the build menu
func hide_menu() -> void:
	if not is_open:
		return

	is_open = false
	visible = false

	# Recapture mouse for FPS controls
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	menu_closed.emit()

## Toggle menu visibility
func toggle_menu() -> void:
	if is_open:
		hide_menu()
	else:
		show_menu()

func _process(_delta: float) -> void:
	if not is_open:
		return

	# Close menu with Escape, B button, Y button, or when selecting a piece
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("toggle_inventory"):
		hide_menu()
		return

	# D-pad navigation
	if Input.is_action_just_pressed("hotbar_unequip"):  # D-pad Down
		_move_selection(1)
	elif Input.is_action_just_pressed("hotbar_equip"):  # D-pad Up
		_move_selection(-1)

	# A button to select piece (will auto-close in _select_current_piece)
	if Input.is_action_just_pressed("interact"):
		_select_current_piece()

## Move selection up/down in the list
func _move_selection(direction: int) -> void:
	selected_index += direction

	# Wrap around
	if selected_index < 0:
		selected_index = available_pieces.size() - 1
	elif selected_index >= available_pieces.size():
		selected_index = 0

	_update_selection_visual()
	print("[BuildMenu] Selected index: %d (%s)" % [selected_index, available_pieces[selected_index]])

## Update visual highlight for selected button
func _update_selection_visual() -> void:
	if not piece_list:
		return

	var buttons = piece_list.get_children()
	for i in buttons.size():
		if buttons[i] is Button:
			if i == selected_index:
				buttons[i].modulate = Color(1.5, 1.5, 1.0)  # Highlight selected
				buttons[i].grab_focus()
			else:
				buttons[i].modulate = Color.WHITE  # Normal

## Select the currently highlighted piece
func _select_current_piece() -> void:
	if selected_index >= 0 and selected_index < available_pieces.size():
		var piece_name = available_pieces[selected_index]
		_on_piece_button_pressed(piece_name)
