extends Node3D

## BloodSparkEffect - Dramatic particle burst when hitting enemies
## Combines blood droplets and sparks for satisfying combat feedback
## Auto-destroys after particles finish

@export var blood_color: Color = Color(0.8, 0.1, 0.05, 1.0)
@export var spark_color: Color = Color(1.0, 0.9, 0.6, 1.0)

func _ready() -> void:
	# Start all particle emitters
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = true

	# Destroy after longest particle lifetime + buffer
	await get_tree().create_timer(1.0).timeout
	queue_free()

## Set the hit direction for directional particle emission
func set_hit_direction(direction: Vector3) -> void:
	# Rotate particles to spray in hit direction
	if direction.length() > 0.1:
		look_at(global_position + direction, Vector3.UP)
