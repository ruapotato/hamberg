extends StaticBody3D

const FloatingText = preload("res://client/ui/floating_text.gd")

## CollectibleBush2D - Small bushes that break instantly when punched
## Drops wood and plant fiber. Respawns after 60 seconds.

# Bush stats
var max_health: float = 1.0
var current_health: float = 1.0
var is_destroyed: bool = false

# Interface compatibility
var chunk_position: Vector2i = Vector2i.ZERO
var object_type: String = "bush_2d"
var object_id: int = -1
var required_tool_type: String = "any"

# Resource drops
var resource_drops: Dictionary = {"wood": 1, "plant_fiber": 1}

# Respawn
var respawn_timer: float = 0.0
const RESPAWN_TIME: float = 60.0
var _waiting_respawn: bool = false

# VFX state
var _sprite_ref: Sprite3D = null


func _ready() -> void:
	add_to_group("destructible_bushes")
	for child in get_children():
		if child is Sprite3D:
			_sprite_ref = child
			break


func _process(delta: float) -> void:
	if _waiting_respawn:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()


func get_object_type() -> String:
	return object_type


func get_object_id() -> int:
	return object_id


func can_be_damaged_by(_tool_type: String) -> bool:
	return true  # Any weapon or fists can break bushes


func get_required_tool_type() -> String:
	return required_tool_type


## Take damage from player attack (client-side)
## Returns true if destroyed
func take_damage_local(damage: float) -> bool:
	if is_destroyed:
		return false

	current_health -= damage
	print("[CollectibleBush2D] Bush took %.1f damage" % damage)

	# Play bush break sound
	SoundManager.play_sound_varied("bush_break", global_position)

	# Spawn leaf particles
	_spawn_leaf_particles()

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false


func _spawn_leaf_particles() -> void:
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.amount = 8
	particles.lifetime = 0.4
	particles.one_shot = true
	particles.explosiveness = 1.0

	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -6.0, 0)
	mat.color = Color(0.3, 0.55, 0.2)  # Green leaf color
	particles.process_material = mat

	var mesh = SphereMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.04
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0, 0.5, 0)
	add_child(particles)

	var timer = get_tree().create_timer(0.6)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())


func _on_destroyed() -> void:
	is_destroyed = true
	print("[CollectibleBush2D] Bush destroyed! Dropping: %s" % resource_drops)

	# Notify server that this bush was destroyed (for persistence)
	var tree_id = get_meta("tree_id", "")
	if tree_id != "":
		NetworkManager.rpc_notify_2d_object_destroyed.rpc_id(1, tree_id)

	# Request server to spawn world items that any player can pick up
	var drops_json := JSON.stringify(resource_drops)
	NetworkManager.rpc_request_spawn_2d_drops.rpc_id(1, drops_json, global_position.x, global_position.y, global_position.z)

	# Floating loot text (client-side eye candy only)
	for item_name in resource_drops:
		var amount: int = resource_drops[item_name]
		var color: Color = FloatingText.RESOURCE_COLORS.get(item_name, Color.WHITE)
		var ft = FloatingText.new()
		ft.setup("+%d %s" % [amount, item_name.capitalize()], color)
		get_tree().current_scene.add_child(ft)
		ft.global_position = global_position + Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3))

	# Hide bush and disable collision
	visible = false
	var col = get_child(0) as CollisionShape3D
	if col:
		col.disabled = true

	# If this bush has a persistent ID, it stays destroyed (server tracks it)
	# Otherwise fall back to local respawn timer
	if tree_id == "":
		_waiting_respawn = true
		respawn_timer = RESPAWN_TIME


func _respawn() -> void:
	_waiting_respawn = false
	is_destroyed = false
	current_health = max_health
	visible = true
	# Re-enable collision
	var col = get_child(0) as CollisionShape3D
	if col:
		col.disabled = false
	if _sprite_ref:
		_sprite_ref.modulate = Color(1, 1, 1, 1)
	print("[CollectibleBush2D] Bush respawned")
