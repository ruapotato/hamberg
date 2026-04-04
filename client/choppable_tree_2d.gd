extends StaticBody3D

## ChoppableTree2D - Adds damage/interaction to 2D billboard trees
## These are client-side trees spawned by EnvironmentSpawner2D.
## When hit with an axe, they take damage and drop wood when destroyed.

# Tree stats
var max_health: float = 80.0
var current_health: float = 80.0
var is_destroyed: bool = false

# Interface compatibility (matches EnvironmentalObject)
var chunk_position: Vector2i = Vector2i.ZERO
var object_type: String = "tree_2d"
var object_id: int = -1
var required_tool_type: String = "axe"

# Resource drops
var resource_drops: Dictionary = {"wood": 3}

# Health bar
var health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

# Reference to spawner for cleanup
var spawner: Node = null


func _ready() -> void:
	add_to_group("destructible_trees")


func get_object_type() -> String:
	return object_type


func get_object_id() -> int:
	return object_id


func can_be_damaged_by(tool_type: String) -> bool:
	if required_tool_type.is_empty() or required_tool_type == "any":
		return true
	return tool_type == required_tool_type


func get_required_tool_type() -> String:
	return required_tool_type


## Take damage from player attack (client-side)
## Returns true if destroyed
func take_damage_local(damage: float) -> bool:
	if is_destroyed:
		return false

	current_health -= damage
	print("[ChoppableTree2D] Tree took %.1f damage (%.1f/%.1f HP)" % [damage, current_health, max_health])

	# Play chop sound
	SoundManager.play_sound_varied("tree_chop", global_position)

	# Create health bar on first damage
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		health_bar.set_height_offset(3.0)

	# Update health bar
	if health_bar:
		health_bar.update_health(current_health, max_health)

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false


func _on_destroyed() -> void:
	is_destroyed = true
	print("[ChoppableTree2D] Tree destroyed! Dropping: %s" % resource_drops)

	# Give items directly to local player
	var players = get_tree().get_nodes_in_group("local_player")
	if players.size() > 0:
		var player = players[0]
		for item_name in resource_drops:
			var amount: int = resource_drops[item_name]
			if player.has_method("pickup_item"):
				player.pickup_item(item_name, amount)

	# Play destruction effect
	_play_destruction_effect()


func _play_destruction_effect() -> void:
	# Play tree fall sound
	SoundManager.play_sound_varied("tree_fall", global_position)

	# Scale-down animation then hide (return to pool)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(_return_to_pool)


func _return_to_pool() -> void:
	# Hide and reset for pool reuse
	visible = false
	is_destroyed = false
	current_health = max_health
	scale = Vector3.ONE
	if health_bar:
		health_bar.queue_free()
		health_bar = null
