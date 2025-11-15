extends Control

## BuildMenu - Shows available building pieces when hammer is equipped
## Opens with right-click, closes when piece is selected

signal piece_selected(piece_name: String)
signal menu_closed()

var available_pieces: Array = [
	"workbench",
	"wooden_wall",
	"wooden_floor",
	"wooden_door",
	"wooden_beam",
	"wooden_roof"
]

var is_open: bool = false

@onready var panel: Panel = $Panel
@onready var piece_list: VBoxContainer = $Panel/PieceList

func _ready() -> void:
	_populate_piece_list()
	hide_menu()

func _populate_piece_list() -> void:
	if not piece_list:
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

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("[BuildMenu] Opened - Select a building piece")

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
	# Close menu with Escape or right-click again
	if is_open and (Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("secondary_action")):
		hide_menu()
