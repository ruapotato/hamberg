extends Node3D

## HealthBar3D - Floating health bar for enemies and objects
## Always faces the camera

@onready var progress_bar: ProgressBar = $SubViewport/ProgressBar
@onready var sprite: Sprite3D = $Sprite3D
@onready var subviewport: SubViewport = $SubViewport

var max_health: float = 100.0
var current_health: float = 100.0

func _ready() -> void:
	# Set up the sprite to display the viewport texture
	sprite.texture = subviewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	# Initialize progress bar
	if progress_bar:
		progress_bar.max_value = max_health
		progress_bar.value = current_health

# NOTE: Removed _process - billboard mode handles camera facing automatically

## Update the health bar
func update_health(health: float, max_hp: float) -> void:
	current_health = health
	max_health = max_hp

	if progress_bar:
		progress_bar.max_value = max_health
		progress_bar.value = current_health

		# Hide if at full health
		visible = current_health < max_health

## Set the height offset above the entity
func set_height_offset(offset: float) -> void:
	position.y = offset
