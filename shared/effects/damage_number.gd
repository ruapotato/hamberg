extends Node3D

## DamageNumber - Floating damage text that rises and fades
## Shows damage dealt with different styles for crits

@onready var label: Label3D = $Label3D

var velocity := Vector3.ZERO
var lifetime := 0.0
const MAX_LIFETIME := 1.0
const RISE_SPEED := 2.0
const DRIFT_SPEED := 0.5

# Pop animation for crits (no tweens)
var _pop_timer: float = 0.0
var _is_crit: bool = false

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
	_is_crit = is_crit

	if is_crit:
		# Critical hit: gold color, larger, with "CRIT!" prefix
		label.text = damage_text + "!"
		label.modulate = Color(1.0, 0.85, 0.2, 1.0)  # Gold
		label.outline_modulate = Color(0.8, 0.3, 0.0, 1.0)  # Orange outline
		label.font_size = 48
		# Start pop animation (no tweens)
		scale = Vector3(0.5, 0.5, 0.5)
		_pop_timer = 0.2
	else:
		# Normal hit: white/light color
		label.text = damage_text
		label.modulate = Color(1.0, 1.0, 1.0, 1.0)  # White
		label.outline_modulate = Color(0.2, 0.2, 0.2, 1.0)  # Dark outline
		label.font_size = 32

func _process(delta: float) -> void:
	lifetime += delta

	# Handle crit pop animation (no tweens)
	if _pop_timer > 0:
		_pop_timer -= delta
		var pop_progress := 1.0 - (_pop_timer / 0.2)
		if pop_progress < 0.5:
			# Scale up to 1.2
			var s := lerpf(0.5, 1.2, pop_progress * 2.0)
			scale = Vector3(s, s, s)
		else:
			# Scale down to 1.0
			var s := lerpf(1.2, 1.0, (pop_progress - 0.5) * 2.0)
			scale = Vector3(s, s, s)

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
