extends Control

## PlayerHUD - Displays player health, stamina, and brain power bars

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var brain_power_bar: ProgressBar = $MarginContainer/VBoxContainer/BrainPowerBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/Label
@onready var stamina_label: Label = $MarginContainer/VBoxContainer/StaminaBar/Label
@onready var brain_power_label: Label = $MarginContainer/VBoxContainer/BrainPowerBar/Label
@onready var fps_label: Label = $FPSLabel

var player: CharacterBody3D = null

func _ready() -> void:
	# Start hidden until player is set
	visible = false

## Link this HUD to a player
func set_player(p: CharacterBody3D) -> void:
	player = p
	visible = true
	_update_bars()

func _process(_delta: float) -> void:
	if player and is_instance_valid(player):
		_update_bars()

	# Update FPS counter
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

## Update health, stamina, and brain power bars
func _update_bars() -> void:
	if not player:
		return

	# Health
	var max_health = player.MAX_HEALTH if "MAX_HEALTH" in player else 100.0
	var health = player.health if "health" in player else max_health
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "HP: %d / %d" % [health, max_health]

	# Stamina
	var max_stamina = player.MAX_STAMINA if "MAX_STAMINA" in player else 100.0
	var stamina = player.stamina if "stamina" in player else max_stamina
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	stamina_label.text = "Stamina: %d / %d" % [stamina, max_stamina]

	# Brain Power
	var max_brain_power = player.MAX_BRAIN_POWER if "MAX_BRAIN_POWER" in player else 100.0
	var brain_power = player.brain_power if "brain_power" in player else max_brain_power
	brain_power_bar.max_value = max_brain_power
	brain_power_bar.value = brain_power
	brain_power_label.text = "BP: %d / %d" % [brain_power, max_brain_power]
