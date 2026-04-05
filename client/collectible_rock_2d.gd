extends StaticBody3D

const FloatingText = preload("res://client/ui/floating_text.gd")

## CollectibleRock2D - Rocks that can be mined for stone
## Takes a few punches (HP 3), or 1 hit with a pickaxe (double damage).
## Drops 2 stone. No respawn (persistent via destroyed objects system).

# Rock stats
var max_health: float = 3.0
var current_health: float = 3.0
var is_destroyed: bool = false

# Interface compatibility
var chunk_position: Vector2i = Vector2i.ZERO
var object_type: String = "rock_2d"
var object_id: int = -1
var required_tool_type: String = "any"

# Resource drops
var resource_drops: Dictionary = {"stone": 2}

# VFX state
var _sprite_ref: Sprite3D = null


func _ready() -> void:
	add_to_group("destructible_rocks")
	for child in get_children():
		if child is Sprite3D:
			_sprite_ref = child
			break


func get_object_type() -> String:
	return object_type


func get_object_id() -> int:
	return object_id


func can_be_damaged_by(_tool_type: String) -> bool:
	return true  # Any weapon or fists can hit rocks


func get_required_tool_type() -> String:
	return required_tool_type


## Take damage from player attack (client-side)
## Returns true if destroyed
func take_damage_local(damage: float) -> bool:
	if is_destroyed:
		return false

	# Pickaxe does double damage
	var players = get_tree().get_nodes_in_group("local_player")
	if players.size() > 0:
		var player = players[0]
		if player.has_method("get_equipped_item"):
			var equipped = player.get_equipped_item()
			if equipped is String and "pickaxe" in equipped.to_lower():
				damage *= 2.0

	current_health -= damage
	print("[CollectibleRock2D] Rock took %.1f damage (%.1f remaining)" % [damage, current_health])

	# Play rock break sound at low pitch for hit, normal for destroy
	SoundManager.play_sound_varied("rock_break", global_position, 0.0, 0.15)

	# Spawn rock particles (gray)
	_spawn_rock_particles()

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false


func _spawn_rock_particles() -> void:
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
	mat.color = Color(0.55, 0.53, 0.50)  # Gray rock color
	particles.process_material = mat

	var mesh = SphereMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.04
	particles.draw_pass_1 = mesh

	particles.position = Vector3(0, 0.3, 0)
	add_child(particles)

	var timer = get_tree().create_timer(0.6)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())


func _on_destroyed() -> void:
	is_destroyed = true
	print("[CollectibleRock2D] Rock destroyed! Dropping: %s" % resource_drops)

	# Notify server that this rock was destroyed (for persistence)
	var tree_id = get_meta("tree_id", "")
	if tree_id != "":
		NetworkManager.rpc_notify_2d_object_destroyed.rpc_id(1, tree_id)

	# Request items from server (server-authoritative inventory)
	for item_name in resource_drops:
		var amount: int = resource_drops[item_name]
		var loot_id: String = (tree_id + "_" + item_name) if tree_id != "" else ("rock_loot_%d_%s" % [get_instance_id(), item_name])
		NetworkManager.rpc_request_pickup_item.rpc_id(1, item_name, amount, loot_id)
		# Floating loot text
		var color: Color = FloatingText.RESOURCE_COLORS.get(item_name, Color.WHITE)
		var ft = FloatingText.new()
		ft.setup("+%d %s" % [amount, item_name.capitalize()], color)
		get_tree().current_scene.add_child(ft)
		ft.global_position = global_position + Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3))

	# Hide rock and disable collision
	visible = false
	var col = get_child(0) as CollisionShape3D
	if col:
		col.disabled = true
	# No respawn - persistent destruction tracked by server
