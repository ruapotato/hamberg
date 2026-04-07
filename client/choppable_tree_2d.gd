extends StaticBody3D

const FloatingText = preload("res://client/ui/floating_text.gd")

## ChoppableTree2D - Adds damage/interaction to 2D billboard trees
## These are client-side trees spawned by EnvironmentSpawner2D.
## When hit with an axe, they take damage and drop wood when destroyed.

# Tree stats
var max_health: float = 30.0
var current_health: float = 30.0
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

# VFX state
var _shake_timer: float = 0.0
var _shake_duration: float = 0.3
var _is_shaking: bool = false
var _sprite_ref: Sprite3D = null  # Cached sprite reference
var _damage_tint_tween: Tween = null
var _is_falling: bool = false


func _ready() -> void:
	add_to_group("destructible_trees")
	# Cache the sprite reference (added by EnvironmentSpawner2D)
	for child in get_children():
		if child is Sprite3D:
			_sprite_ref = child
			break


func _process(delta: float) -> void:
	if _is_shaking and _sprite_ref:
		_shake_timer += delta
		var t = _shake_timer / _shake_duration
		if t >= 1.0:
			_is_shaking = false
			_sprite_ref.position.x = 0.0
		else:
			# Sine wave decay shake
			_sprite_ref.position.x = sin(_shake_timer * 30.0) * 0.1 * (1.0 - t)


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

	# Start shake effect
	_is_shaking = true
	_shake_timer = 0.0

	# Flash white on hit (damage tint)
	_flash_damage_tint()

	# Spawn hit particles
	_spawn_hit_particles()

	# Create health bar on first damage — position above the tree sprite
	if not health_bar:
		health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(health_bar)
		# Scale health bar height to tree size
		var sprite = get_node_or_null("TreeSprite")
		var tree_height := 2.5
		if sprite and sprite.texture:
			tree_height = sprite.texture.get_height() * sprite.pixel_size * sprite.scale.y + 0.3
		health_bar.set_height_offset(tree_height)

	# Update health bar
	if health_bar:
		health_bar.update_health(current_health, max_health)

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false


func _flash_damage_tint() -> void:
	if not _sprite_ref:
		return
	# Kill any existing tint tween
	if _damage_tint_tween and _damage_tint_tween.is_valid():
		_damage_tint_tween.kill()
	# Flash white
	_sprite_ref.modulate = Color(3.0, 3.0, 3.0, 1.0)
	_damage_tint_tween = create_tween()
	_damage_tint_tween.tween_property(_sprite_ref, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)


func _spawn_hit_particles() -> void:
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.amount = 10
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 1.0

	# Process material for particle behavior
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.color = Color(0.55, 0.35, 0.15)  # Brown wood color
	particles.process_material = mat

	# Draw pass - small sphere mesh
	var mesh = SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	particles.draw_pass_1 = mesh

	# Position at hit point (center of tree, slightly up)
	particles.position = Vector3(0, 1.5, 0)

	add_child(particles)

	# Auto-remove after particles finish
	var timer = get_tree().create_timer(0.5)
	timer.timeout.connect(func(): if is_instance_valid(particles): particles.queue_free())


func _on_destroyed() -> void:
	is_destroyed = true
	print("[ChoppableTree2D] Tree destroyed! Dropping: %s" % resource_drops)

	# Notify server that this tree was destroyed (for persistence)
	var tree_id = get_meta("tree_id", "")
	if tree_id != "":
		NetworkManager.rpc_notify_2d_object_destroyed.rpc_id(1, tree_id)

	# Spawn a stump at the tree's base position
	_spawn_stump()

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

	# Play destruction effect (fall animation)
	_play_destruction_effect()


func _play_destruction_effect() -> void:
	# Play tree fall sound
	SoundManager.play_sound_varied("tree_fall", global_position)

	_is_falling = true
	_is_shaking = false
	if _sprite_ref:
		_sprite_ref.position.x = 0.0

	# Disable collision immediately so player can walk through
	var col = get_child(0) as CollisionShape3D
	if col:
		col.disabled = true

	# Fall animation: tilt 90 degrees over 1 second, then scale down and remove
	var tween := create_tween()
	# Random fall direction
	var fall_dir = 1.0 if randf() > 0.5 else -1.0
	tween.tween_property(self, "rotation:z", fall_dir * PI / 2.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale:y", 0.0, 0.5).set_delay(0.5)
	tween.tween_callback(_return_to_pool)


func _return_to_pool() -> void:
	# Hide and reset for pool reuse
	visible = false
	is_destroyed = false
	_is_falling = false
	current_health = max_health
	scale = Vector3.ONE
	rotation = Vector3.ZERO
	# Re-enable collision for next use
	var col = get_child(0) as CollisionShape3D
	if col:
		col.disabled = false
	if _sprite_ref:
		_sprite_ref.position.x = 0.0
		_sprite_ref.modulate = Color(1, 1, 1, 1)
	if health_bar:
		health_bar.queue_free()
		health_bar = null


func _spawn_stump() -> void:
	# Save position before any tree state changes
	var stump_pos: Vector3 = position  # Tree body position (already at ground level)

	var stump_tex: Texture2D = load("res://assets/textures/environment/stump.png")
	if not stump_tex:
		return

	# Create a destructible stump (punchable for 1 extra wood)
	var CollectibleBush = preload("res://client/collectible_bush_2d.gd")
	var stump_body := StaticBody3D.new()
	stump_body.set_script(CollectibleBush)
	stump_body.collision_layer = 1
	stump_body.collision_mask = 0

	# Small collision shape
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.4, 0.5)
	col.shape = box
	col.position = Vector3(0, 0.2, 0)
	stump_body.add_child(col)

	# Stump billboard sprite
	var sprite := Sprite3D.new()
	sprite.texture = stump_tex
	sprite.pixel_size = 0.008
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var stump_height: float = stump_tex.get_height() * sprite.pixel_size
	sprite.position = Vector3(0, stump_height * 0.35, 0)
	stump_body.add_child(sprite)

	# Configure as collectible (1 HP, drops 1 wood, no respawn)
	stump_body.position = stump_pos
	get_tree().current_scene.add_child(stump_body)
	stump_body.max_health = 1.0
	stump_body.current_health = 1.0
	stump_body.resource_drops = {"wood": 1}
	stump_body.is_destroyed = false
	# Override: permanently remove on destroy (no respawn timer)
	stump_body.set_meta("no_respawn", true)
	stump_body.set_meta("permanent_destroy", true)
