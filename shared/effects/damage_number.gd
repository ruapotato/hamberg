extends Node3D

## DamageNumber - Floating damage text that rises and fades
## Shows damage dealt with different styles for crits

@onready var label: Label3D = $Label3D

var velocity := Vector3.ZERO
var lifetime := 0.0
const MAX_LIFETIME := 1.0
const RISE_SPEED := 2.0
const DRIFT_SPEED := 0.5

func _ready() -> void:
	# Random horizontal drift for visual variety
	velocity = Vector3(
		randf_range(-DRIFT_SPEED, DRIFT_SPEED),
		RISE_SPEED,
		randf_range(-DRIFT_SPEED, DRIFT_SPEED)
	)

func setup(damage: float, is_crit: bool) -> void:
	if not label:
		label = $Label3D

	# Format damage as integer
	var damage_text := str(int(damage))

	if is_crit:
		# Critical hit: gold color, larger, with "CRIT!" prefix
		label.text = damage_text + "!"
		label.modulate = Color(1.0, 0.85, 0.2, 1.0)  # Gold
		label.outline_modulate = Color(0.8, 0.3, 0.0, 1.0)  # Orange outline
		label.font_size = 48
		# Start with a pop scale animation
		scale = Vector3(0.5, 0.5, 0.5)
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
		tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
	else:
		# Normal hit: white/light color
		label.text = damage_text
		label.modulate = Color(1.0, 1.0, 1.0, 1.0)  # White
		label.outline_modulate = Color(0.2, 0.2, 0.2, 1.0)  # Dark outline
		label.font_size = 32

func _process(delta: float) -> void:
	lifetime += delta

	# Move upward with drift
	global_position += velocity * delta

	# Slow down over time
	velocity.y = RISE_SPEED * (1.0 - lifetime / MAX_LIFETIME)

	# Fade out
	if label:
		var alpha = 1.0 - (lifetime / MAX_LIFETIME)
		label.modulate.a = alpha
		label.outline_modulate.a = alpha

	# Destroy when done
	if lifetime >= MAX_LIFETIME:
		queue_free()
