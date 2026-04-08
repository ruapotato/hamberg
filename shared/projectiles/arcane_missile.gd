extends Projectile

## Arcane Missile - Homing projectile that tracks the nearest enemy

var target: Node3D = null
var turn_speed: float = 3.0
var search_radius: float = 20.0

func _ready() -> void:
	super._ready()
	# Find nearest enemy to track
	_acquire_target()

func _physics_process(delta: float) -> void:
	if has_hit:
		return

	# Re-acquire if target lost
	if target and not is_instance_valid(target):
		target = null
		_acquire_target()

	# Home toward target
	if target and is_instance_valid(target):
		var to_target := (target.global_position + Vector3(0, 1, 0) - global_position).normalized()
		var current_dir := velocity.normalized()
		var new_dir := current_dir.lerp(to_target, turn_speed * delta).normalized()
		velocity = new_dir * velocity.length()

		if velocity.length() > 0.01:
			var look_target := global_position + velocity.normalized()
			if global_position.distance_to(look_target) > 0.01:
				look_at(look_target, Vector3.UP)

	position += velocity * delta

func _acquire_target() -> void:
	var best_dist := search_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			var dist := global_position.distance_to(node.global_position)
			if dist < best_dist:
				best_dist = dist
				target = node
