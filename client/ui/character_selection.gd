extends Control

signal character_selected(character_id: String, character_name: String, is_new: bool)

@onready var character_list_vbox: VBoxContainer = $Panel/VBox/CharacterList/VBox
@onready var name_input: LineEdit = $Panel/VBox/NewCharacterHBox/NameInput
@onready var create_button: Button = $Panel/VBox/NewCharacterHBox/CreateButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

var characters: Array = []
var character_button_scene: PackedScene
var selected_index: int = 0  # For controller navigation

func _ready() -> void:
	create_button.pressed.connect(_on_create_button_pressed)

	# Create character button scene programmatically
	character_button_scene = _create_character_button_scene()

func _process(_delta: float) -> void:
	if not visible:
		return

	# D-pad up/down to navigate characters
	if Input.is_action_just_pressed("hotbar_equip"):  # D-pad Up
		_move_selection(-1)
	elif Input.is_action_just_pressed("hotbar_unequip"):  # D-pad Down
		_move_selection(1)

	# A button to select character
	if Input.is_action_just_pressed("interact"):
		_select_current_character()

func show_characters(character_data: Array) -> void:
	characters = character_data

	# Clear existing character buttons
	for child in character_list_vbox.get_children():
		child.queue_free()

	if characters.is_empty():
		status_label.text = "No characters found. Create a new one!"
		selected_index = -1  # No characters to select
	else:
		status_label.text = ""
		selected_index = 0  # Select first character

		# Create button for each character
		for char_data in characters:
			var button = _create_character_button(char_data)
			character_list_vbox.add_child(button)

		_update_selection_visual()

	visible = true

func _create_character_button_scene() -> PackedScene:
	# Create a simple button scene for characters
	var scene = PackedScene.new()
	return scene

func _create_character_button(char_data: Dictionary) -> Button:
	var button = Button.new()
	button.custom_minimum_size = Vector2(0, 60)

	var character_id = char_data.get("character_id", "")
	var character_name = char_data.get("character_name", "Unknown")
	var last_played = char_data.get("last_played", 0)
	var play_time = char_data.get("play_time", 0)

	# Format last played time
	var time_str = _format_timestamp(last_played)

	# Create button text
	var button_text = "%s\nLast played: %s" % [character_name, time_str]
	button.text = button_text

	# Connect button press
	button.pressed.connect(_on_character_button_pressed.bind(character_id, character_name))

	return button

func _on_character_button_pressed(character_id: String, character_name: String) -> void:
	print("[CharacterSelection] Selected character: %s (%s)" % [character_name, character_id])
	character_selected.emit(character_id, character_name, false)
	visible = false

func _on_create_button_pressed() -> void:
	var new_name = name_input.text.strip_edges()

	if new_name.is_empty():
		status_label.text = "Please enter a character name"
		status_label.modulate = Color.RED
		return

	if new_name.length() > 20:
		status_label.text = "Name too long (max 20 characters)"
		status_label.modulate = Color.RED
		return

	print("[CharacterSelection] Creating new character: %s" % new_name)

	# Generate a temporary character_id (will be replaced by server)
	var temp_id = "temp_" + str(Time.get_ticks_msec())

	character_selected.emit(temp_id, new_name, true)
	visible = false

func _format_timestamp(unix_time: int) -> String:
	if unix_time == 0:
		return "Never"

	var time_dict = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [
		time_dict.year,
		time_dict.month,
		time_dict.day,
		time_dict.hour,
		time_dict.minute
	]

## Move selection up/down (controller D-pad)
func _move_selection(direction: int) -> void:
	if characters.is_empty():
		return

	selected_index += direction

	# Wrap around
	if selected_index < 0:
		selected_index = characters.size() - 1
	elif selected_index >= characters.size():
		selected_index = 0

	_update_selection_visual()

## Update visual highlight for selected character
func _update_selection_visual() -> void:
	if not character_list_vbox:
		return

	var buttons = character_list_vbox.get_children()
	for i in buttons.size():
		if buttons[i] is Button:
			if i == selected_index:
				buttons[i].modulate = Color(1.5, 1.5, 1.0)  # Highlight selected
				buttons[i].grab_focus()
			else:
				buttons[i].modulate = Color.WHITE  # Normal

## Select the currently highlighted character (controller A button)
func _select_current_character() -> void:
	if selected_index >= 0 and selected_index < characters.size():
		var char_data = characters[selected_index]
		var character_id = char_data.get("character_id", "")
		var character_name = char_data.get("character_name", "Unknown")
		_on_character_button_pressed(character_id, character_name)
