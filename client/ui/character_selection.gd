extends Control

signal character_selected(character_id: String, character_name: String, is_new: bool)

@onready var character_list_vbox: VBoxContainer = $Panel/VBox/CharacterList/VBox
@onready var name_input: LineEdit = $Panel/VBox/NewCharacterHBox/NameInput
@onready var create_button: Button = $Panel/VBox/NewCharacterHBox/CreateButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

const COLOR_BLUE := Color("#0014ff")
const COLOR_GOLD := Color("#ffeb00")
const COLOR_PINK := Color("#ff0093")
const COLOR_GREEN := Color("#00ff6c")
const COLOR_DARK_BG := Color(0.04, 0.04, 0.12, 1.0)
const COLOR_PANEL_BG := Color(0.06, 0.06, 0.18, 0.92)
const COLOR_INPUT_BG := Color(0.03, 0.03, 0.1, 1.0)

var characters: Array = []
var character_button_scene: PackedScene
var selected_index: int = 0  # For controller navigation
var _char_button_normal_style: StyleBoxFlat
var _char_button_hover_style: StyleBoxFlat
var _char_button_focus_style: StyleBoxFlat

func _ready() -> void:
	create_button.pressed.connect(_on_create_button_pressed)
	create_button.mouse_entered.connect(func(): SoundManager.play_ui_sound("ui_hover"))

	# Create character button scene programmatically
	character_button_scene = _create_character_button_scene()

	_apply_theme()

func _apply_theme() -> void:
	# --- Panel styling ---
	var panel := $Panel as Panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(COLOR_BLUE, 0.6)
	panel_style.shadow_color = Color(COLOR_BLUE, 0.15)
	panel_style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", panel_style)

	# --- Title "HAMBERG" ---
	var title := $Panel/VBox/Title as Label
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", COLOR_GOLD)

	# --- Subtitle ---
	var subtitle := $Panel/VBox/Subtitle as Label
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))

	# --- "SELECT CHARACTER" label ---
	var select_label := $Panel/VBox/SelectLabel as Label
	select_label.add_theme_font_size_override("font_size", 14)
	select_label.add_theme_color_override("font_color", Color(COLOR_BLUE.lightened(0.5), 0.8))

	# --- "CREATE NEW CHARACTER" label ---
	var new_char_label := $Panel/VBox/NewCharLabel as Label
	new_char_label.add_theme_font_size_override("font_size", 14)
	new_char_label.add_theme_color_override("font_color", Color(COLOR_BLUE.lightened(0.5), 0.8))

	# --- Character list scroll container ---
	var char_list := $Panel/VBox/CharacterList as ScrollContainer
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.02, 0.02, 0.08, 0.7)
	list_style.corner_radius_top_left = 8
	list_style.corner_radius_top_right = 8
	list_style.corner_radius_bottom_left = 8
	list_style.corner_radius_bottom_right = 8
	list_style.content_margin_left = 8
	list_style.content_margin_right = 8
	list_style.content_margin_top = 8
	list_style.content_margin_bottom = 8
	list_style.border_width_left = 1
	list_style.border_width_top = 1
	list_style.border_width_right = 1
	list_style.border_width_bottom = 1
	list_style.border_color = Color(COLOR_BLUE, 0.3)
	char_list.add_theme_stylebox_override("panel", list_style)

	# --- Pre-build character button styles ---
	_char_button_normal_style = _make_button_style(Color(0.08, 0.08, 0.22, 0.8), Color(COLOR_BLUE, 0.4))
	_char_button_hover_style = _make_button_style(Color(0.1, 0.1, 0.3, 0.9), COLOR_GOLD)
	_char_button_focus_style = _make_button_style(Color(0.1, 0.1, 0.3, 0.9), COLOR_GOLD)

	# --- Name input field ---
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = COLOR_INPUT_BG
	input_style.corner_radius_top_left = 6
	input_style.corner_radius_top_right = 6
	input_style.corner_radius_bottom_left = 6
	input_style.corner_radius_bottom_right = 6
	input_style.border_width_left = 2
	input_style.border_width_top = 2
	input_style.border_width_right = 2
	input_style.border_width_bottom = 2
	input_style.border_color = Color(COLOR_BLUE, 0.5)
	input_style.content_margin_left = 10
	input_style.content_margin_right = 10
	input_style.content_margin_top = 6
	input_style.content_margin_bottom = 6
	name_input.add_theme_stylebox_override("normal", input_style)

	var input_focus_style := input_style.duplicate()
	input_focus_style.border_color = COLOR_BLUE
	name_input.add_theme_stylebox_override("focus", input_focus_style)
	name_input.add_theme_color_override("font_color", Color.WHITE)
	name_input.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	name_input.add_theme_color_override("caret_color", COLOR_GOLD)
	name_input.add_theme_font_size_override("font_size", 16)
	name_input.custom_minimum_size.y = 40

	# --- Create button ---
	_style_action_button(create_button, "CREATE")

	# --- Status label ---
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", COLOR_GREEN)

func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.border_color = border
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _style_action_button(button: Button, _text: String) -> void:
	var normal := _make_button_style(Color(COLOR_BLUE, 0.2), Color(COLOR_BLUE, 0.6))
	var hover := _make_button_style(Color(COLOR_BLUE, 0.35), COLOR_GOLD)
	var pressed := _make_button_style(Color(COLOR_BLUE, 0.5), COLOR_GOLD)
	var focus := hover.duplicate()

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", COLOR_GOLD)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_focus_color", COLOR_GOLD)
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size.y = 40

func _style_character_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _char_button_normal_style)
	button.add_theme_stylebox_override("hover", _char_button_hover_style)
	button.add_theme_stylebox_override("pressed", _char_button_hover_style)
	button.add_theme_stylebox_override("focus", _char_button_focus_style)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", COLOR_GOLD)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_focus_color", COLOR_GOLD)
	button.add_theme_font_size_override("font_size", 16)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

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

	# Apply styled theme
	_style_character_button(button)

	# Connect button press and hover sounds
	button.pressed.connect(_on_character_button_pressed.bind(character_id, character_name))
	button.mouse_entered.connect(func(): SoundManager.play_ui_sound("ui_hover"))

	return button

func _on_character_button_pressed(character_id: String, character_name: String) -> void:
	print("[CharacterSelection] Selected character: %s (%s)" % [character_name, character_id])
	SoundManager.play_ui_sound("ui_confirm")
	character_selected.emit(character_id, character_name, false)
	visible = false

func _on_create_button_pressed() -> void:
	var new_name: String = name_input.text.strip_edges()

	if new_name.is_empty():
		status_label.text = "Please enter a character name"
		status_label.add_theme_color_override("font_color", COLOR_PINK)
		SoundManager.play_ui_sound("ui_cancel")
		return

	if new_name.length() > 20:
		status_label.text = "Name too long (max 20 characters)"
		status_label.add_theme_color_override("font_color", COLOR_PINK)
		SoundManager.play_ui_sound("ui_cancel")
		return

	print("[CharacterSelection] Creating new character: %s" % new_name)
	SoundManager.play_ui_sound("ui_confirm")

	var temp_id: String = "temp_" + str(Time.get_ticks_msec())
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
				buttons[i].modulate = Color.WHITE
				buttons[i].add_theme_color_override("font_color", COLOR_GOLD)
				buttons[i].grab_focus()
			else:
				buttons[i].modulate = Color.WHITE
				buttons[i].add_theme_color_override("font_color", Color.WHITE)

## Select the currently highlighted character (controller A button)
func _select_current_character() -> void:
	if selected_index >= 0 and selected_index < characters.size():
		var char_data = characters[selected_index]
		var character_id = char_data.get("character_id", "")
		var character_name = char_data.get("character_name", "Unknown")
		_on_character_button_pressed(character_id, character_name)
