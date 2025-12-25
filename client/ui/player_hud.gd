extends Control

## PlayerHUD - Displays player health, stamina, brain power bars, and food slots

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var brain_power_bar: ProgressBar = $MarginContainer/VBoxContainer/BrainPowerBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/Label
@onready var stamina_label: Label = $MarginContainer/VBoxContainer/StaminaBar/Label
@onready var brain_power_label: Label = $MarginContainer/VBoxContainer/BrainPowerBar/Label
@onready var fps_label: Label = $FPSLabel

# Food slot UI references
@onready var food_slots_container: VBoxContainer = $MarginContainer/VBoxContainer/FoodSlotsContainer
@onready var food_slot_1: HBoxContainer = $MarginContainer/VBoxContainer/FoodSlotsContainer/FoodSlot1
@onready var food_slot_2: HBoxContainer = $MarginContainer/VBoxContainer/FoodSlotsContainer/FoodSlot2
@onready var food_slot_3: HBoxContainer = $MarginContainer/VBoxContainer/FoodSlotsContainer/FoodSlot3

# Combo indicator (created dynamically)
var combo_container: Control = null
var combo_label: Label = null
var combo_bar: ProgressBar = null

var player: CharacterBody3D = null
var flash_timer: float = 0.0
const FLASH_SPEED: float = 8.0  # Flashes per second

# Food colors for different food types
const FOOD_COLORS: Dictionary = {
	"cooked_venison": Color(0.7, 0.3, 0.2),   # Reddish-brown
	"cooked_pork": Color(0.8, 0.6, 0.5),      # Pinkish
	"cooked_mutton": Color(0.6, 0.4, 0.3),    # Brown
}

func _ready() -> void:
	# Start hidden until player is set
	visible = false
	_create_combo_indicator()

## Link this HUD to a player
func set_player(p: CharacterBody3D) -> void:
	player = p
	visible = true
	_update_bars(0.0)

func _process(delta: float) -> void:
	if player and is_instance_valid(player):
		_update_bars(delta)

	# Update FPS counter
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

## Get current max health from player's food system
func _get_max_health() -> float:
	if player and player.has_node("PlayerFood"):
		return player.get_node("PlayerFood").get_max_health()
	return 25.0  # PC.BASE_HEALTH

## Get current max stamina from player's food system
func _get_max_stamina() -> float:
	if player and player.has_node("PlayerFood"):
		return player.get_node("PlayerFood").get_max_stamina()
	return 50.0  # PC.BASE_STAMINA

## Get current max brain power from player's food system
func _get_max_brain_power() -> float:
	if player and player.has_node("PlayerFood"):
		return player.get_node("PlayerFood").get_max_brain_power()
	return 25.0  # PC.BASE_BRAIN_POWER

## Update health, stamina, and brain power bars
func _update_bars(delta: float = 0.0) -> void:
	if not player:
		return

	# Health (dynamic max from food system)
	var max_health = _get_max_health()
	var health = player.health if "health" in player else max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "HP: %d / %d" % [health, max_health]

	# Stamina (dynamic max from food system)
	var max_stamina = _get_max_stamina()
	var stamina = player.stamina if "stamina" in player else max_stamina
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina

	# Check for exhausted state and flash the stamina bar
	var is_exhausted = player.is_exhausted if "is_exhausted" in player else false
	if is_exhausted:
		flash_timer += delta * FLASH_SPEED
		# Use sin wave for smooth flashing between 0.3 and 1.0 alpha
		var flash_alpha = 0.65 + 0.35 * sin(flash_timer * TAU)
		stamina_bar.modulate.a = flash_alpha
		stamina_label.text = "EXHAUSTED"
	else:
		flash_timer = 0.0
		stamina_bar.modulate.a = 1.0
		stamina_label.text = "Stamina: %d / %d" % [stamina, max_stamina]

	# Brain Power (dynamic max from food system)
	var max_brain_power = _get_max_brain_power()
	var brain_power = player.brain_power if "brain_power" in player else max_brain_power
	brain_power_bar.max_value = max_brain_power
	brain_power_bar.value = brain_power
	brain_power_label.text = "BP: %d / %d" % [brain_power, max_brain_power]

	# Update food slots
	_update_food_slots()

	# Update combo indicator
	_update_combo_indicator()

## Update the food slot display
func _update_food_slots() -> void:
	if not player or not player.has_node("PlayerFood"):
		_hide_all_food_slots()
		return

	var player_food = player.get_node("PlayerFood")
	var active_foods = player_food.get_active_foods_info()

	# Get food slot nodes
	var slots = [food_slot_1, food_slot_2, food_slot_3]

	for i in 3:
		if i < active_foods.size():
			var food_info = active_foods[i]
			_update_food_slot(slots[i], food_info)
			slots[i].visible = true
		else:
			slots[i].visible = false

## Update a single food slot with food info
func _update_food_slot(slot: HBoxContainer, food_info: Dictionary) -> void:
	var icon = slot.get_node("Icon") as ColorRect
	var label = slot.get_node("Label") as Label
	var timer = slot.get_node("Timer") as Label

	var food_id = food_info.get("food_id", "")
	var remaining = food_info.get("remaining_time", 0.0)

	# Set icon color based on food type
	if FOOD_COLORS.has(food_id):
		icon.color = FOOD_COLORS[food_id]
	else:
		icon.color = Color(0.5, 0.5, 0.5)  # Default gray

	# Format food name (remove prefix, capitalize)
	var display_name = food_id.replace("cooked_", "").capitalize()
	label.text = display_name

	# Format timer (mm:ss)
	var minutes = int(remaining) / 60
	var seconds = int(remaining) % 60
	timer.text = "%d:%02d" % [minutes, seconds]

	# Change timer color when low
	if remaining < 60:
		timer.modulate = Color(1.0, 0.5, 0.3)  # Orange when < 1 min
	elif remaining < 120:
		timer.modulate = Color(1.0, 1.0, 0.5)  # Yellow when < 2 min
	else:
		timer.modulate = Color.WHITE

## Hide all food slots
func _hide_all_food_slots() -> void:
	if food_slot_1:
		food_slot_1.visible = false
	if food_slot_2:
		food_slot_2.visible = false
	if food_slot_3:
		food_slot_3.visible = false

## Create combo indicator UI (positioned at center-bottom of screen)
func _create_combo_indicator() -> void:
	# Container for combo indicator
	combo_container = Control.new()
	combo_container.name = "ComboIndicator"
	combo_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	combo_container.position = Vector2(-60, -80)  # Centered, above bottom
	combo_container.size = Vector2(120, 40)
	combo_container.visible = false
	add_child(combo_container)

	# Combo count label (e.g., "COMBO x2")
	combo_label = Label.new()
	combo_label.name = "ComboLabel"
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.position = Vector2(0, 0)
	combo_label.size = Vector2(120, 20)
	combo_label.add_theme_font_size_override("font_size", 16)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))  # Gold
	combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	combo_label.add_theme_constant_override("outline_size", 2)
	combo_container.add_child(combo_label)

	# Combo timer bar (depletes as window expires)
	combo_bar = ProgressBar.new()
	combo_bar.name = "ComboBar"
	combo_bar.position = Vector2(0, 22)
	combo_bar.size = Vector2(120, 12)
	combo_bar.min_value = 0.0
	combo_bar.max_value = 1.0
	combo_bar.value = 1.0
	combo_bar.show_percentage = false

	# Style the combo bar
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bar_style.corner_radius_top_left = 3
	bar_style.corner_radius_top_right = 3
	bar_style.corner_radius_bottom_left = 3
	bar_style.corner_radius_bottom_right = 3
	combo_bar.add_theme_stylebox_override("background", bar_style)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(1.0, 0.6, 0.1)  # Orange
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	combo_bar.add_theme_stylebox_override("fill", fill_style)

	combo_container.add_child(combo_bar)

## Update combo indicator display
func _update_combo_indicator() -> void:
	if not player or not combo_container:
		return

	var combo_count = player.combo_count if "combo_count" in player else 0
	var combo_timer = player.combo_timer if "combo_timer" in player else 0.0
	var combo_window = player.COMBO_WINDOW if "COMBO_WINDOW" in player else 1.2

	# Show combo indicator when in an active combo (count > 0)
	if combo_count > 0 and combo_timer > 0:
		combo_container.visible = true
		combo_label.text = "COMBO x%d" % (combo_count + 1)

		# Bar depletes as timer counts down
		var progress = combo_timer / combo_window
		combo_bar.value = progress

		# Change color based on remaining time
		var fill_style = combo_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if progress < 0.3:
				fill_style.bg_color = Color(1.0, 0.2, 0.2)  # Red when almost expired
			elif progress < 0.6:
				fill_style.bg_color = Color(1.0, 0.8, 0.2)  # Yellow when medium
			else:
				fill_style.bg_color = Color(1.0, 0.6, 0.1)  # Orange when plenty of time
	else:
		combo_container.visible = false
