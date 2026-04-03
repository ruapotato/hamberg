extends Node3D
class_name SpellBase
## Base class for all spells with casting, mana management, and cooldowns

signal spell_cast(spell_id: String)
signal mana_changed(current_mana: int, max_mana: int)
signal casting_started(cast_time: float)
signal casting_finished
signal casting_cancelled
signal cooldown_started(cooldown_time: float)
signal cooldown_finished

@export var spell_id: String = "fireball"
var owner_player: Node = null

# Spell data (loaded from SpellRegistry)
var display_name: String = "Spell"
var description: String = ""
var damage_type: int = 0
var spell_type: int = 0
var spell_tier: int = 1

# Core stats
var base_damage: int = 30
var mana_cost: int = 10
var cast_time: float = 0.5
var cooldown: float = 1.0

# Runtime state
var current_mana: int = 100
var max_mana: int = 100
var mana_regen_per_sec: float = 5.0
var is_casting: bool = false
var is_on_cooldown: bool = false
var can_cast: bool = true

# Spell data instance
var spell_data: SpellData = null

# Effect scenes (to be overridden by subclasses)
var projectile_scene: PackedScene = null
var beam_scene: PackedScene = null
var aoe_scene: PackedScene = null

# Components
@onready var cast_point: Marker3D = $CastPoint if has_node("CastPoint") else null
@onready var cast_timer: Timer = $CastTimer
@onready var cooldown_timer: Timer = $CooldownTimer
@onready var mana_regen_timer: Timer = $ManaRegenTimer
@onready var cast_light: OmniLight3D = $CastPoint/CastLight if has_node("CastPoint/CastLight") else null


func _ready() -> void:
	_setup_timers()
	_load_spell_data()
	current_mana = max_mana
	_start_mana_regen()


func _setup_timers() -> void:
	# Create timers if they don't exist
	if not has_node("CastTimer"):
		cast_timer = Timer.new()
		cast_timer.name = "CastTimer"
		cast_timer.one_shot = true
		add_child(cast_timer)
		cast_timer.timeout.connect(_on_cast_timer_timeout)

	if not has_node("CooldownTimer"):
		cooldown_timer = Timer.new()
		cooldown_timer.name = "CooldownTimer"
		cooldown_timer.one_shot = true
		add_child(cooldown_timer)
		cooldown_timer.timeout.connect(_on_cooldown_timer_timeout)

	if not has_node("ManaRegenTimer"):
		mana_regen_timer = Timer.new()
		mana_regen_timer.name = "ManaRegenTimer"
		mana_regen_timer.wait_time = 0.1  # Regen tick rate
		add_child(mana_regen_timer)
		mana_regen_timer.timeout.connect(_on_mana_regen_timer_timeout)


func _load_spell_data() -> void:
	var data: Dictionary = SpellRegistry.get_spell_data(spell_id)
	if data.is_empty():
		push_warning("Spell data not found for: %s" % spell_id)
		return

	spell_data = SpellData.from_dict(data)

	display_name = spell_data.display_name
	description = spell_data.description
	damage_type = spell_data.damage_type
	spell_type = spell_data.spell_type
	spell_tier = spell_data.spell_tier

	base_damage = spell_data.base_damage
	mana_cost = spell_data.mana_cost
	cast_time = spell_data.cast_time
	cooldown = spell_data.cooldown


func try_cast() -> bool:
	if not can_cast:
		return false

	if is_casting:
		return false

	if is_on_cooldown:
		return false

	if current_mana < mana_cost:
		# Not enough mana
		# TODO: Add AudioManager for "no_mana" sound
		return false

	if not owner_player:
		push_warning("Spell has no owner_player set!")
		return false

	_start_cast()
	return true


func _start_cast() -> void:
	is_casting = true
	can_cast = false

	cast_timer.wait_time = cast_time
	cast_timer.start()

	_play_cast_start_effects()
	casting_started.emit(cast_time)


func _finish_cast() -> void:
	is_casting = false

	# Consume mana
	current_mana -= mana_cost
	current_mana = max(0, current_mana)
	mana_changed.emit(current_mana, max_mana)

	# Execute the spell
	_execute_spell()

	# Start cooldown
	_start_cooldown()

	casting_finished.emit()
	spell_cast.emit(spell_id)


func _execute_spell() -> void:
	# To be overridden by subclasses
	push_warning("SpellBase._execute_spell() should be overridden!")


func cancel_cast() -> void:
	if not is_casting:
		return

	is_casting = false
	can_cast = true
	cast_timer.stop()

	casting_cancelled.emit()


func _start_cooldown() -> void:
	is_on_cooldown = true

	cooldown_timer.wait_time = cooldown
	cooldown_timer.start()

	cooldown_started.emit(cooldown)


func _start_mana_regen() -> void:
	mana_regen_timer.start()


func _regenerate_mana() -> void:
	if current_mana < max_mana:
		var regen_amount := int(mana_regen_per_sec * mana_regen_timer.wait_time)
		current_mana = min(current_mana + regen_amount, max_mana)
		mana_changed.emit(current_mana, max_mana)


func add_mana(amount: int) -> void:
	current_mana = min(current_mana + amount, max_mana)
	mana_changed.emit(current_mana, max_mana)


func _play_cast_start_effects() -> void:
	if not spell_data:
		return

	# TODO: Add AudioManager for cast sounds
	# AudioManager.play_sound_3d(spell_data.cast_sound, global_position, 0.0)

	# Cast light
	if cast_light:
		cast_light.light_color = spell_data.trail_color
		cast_light.light_energy = spell_data.glow_intensity
		cast_light.visible = true


func _play_cast_finish_effects() -> void:
	if cast_light:
		cast_light.visible = false


func get_cast_direction() -> Vector3:
	if not owner_player:
		return -global_transform.basis.z

	var camera: Camera3D = owner_player.get_node("CameraMount/Camera3D")
	if not camera:
		return -global_transform.basis.z

	return -camera.global_transform.basis.z


func get_cast_origin() -> Vector3:
	if cast_point:
		return cast_point.global_position

	if not owner_player:
		return global_position

	var camera: Camera3D = owner_player.get_node("CameraMount/Camera3D")
	if camera:
		return camera.global_position

	return global_position


func raycast_from_camera(max_distance: float = 100.0) -> Dictionary:
	if not owner_player:
		return {}

	# Use player's aim raycast if available
	if owner_player.has_method("get_aim_target"):
		var aim_result: Dictionary = owner_player.get_aim_target()
		if not aim_result.is_empty() and aim_result.get("collider") != null:
			return {
				"position": aim_result.position,
				"normal": aim_result.normal,
				"collider": aim_result.collider
			}

	# Fallback to manual raycast
	var camera: Camera3D = owner_player.get_node("CameraMount/Camera3D")
	if not camera:
		return {}

	var from := camera.global_position
	var direction := get_cast_direction()
	var to := from + direction * max_distance

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b1111  # World, player, enemy, interactable (includes trees)
	query.collide_with_areas = true
	query.exclude = [owner_player]

	return space_state.intersect_ray(query)


## Damage a destructible object (tree, etc.)
func damage_destructible(collider: Node, damage: int, hit_position: Vector3 = Vector3.ZERO) -> void:
	# Check if it's a tree
	if collider.is_in_group("destructible_trees"):
		var spawners = get_tree().get_nodes_in_group("environment_spawner")
		if spawners.size() > 0:
			var spawner = spawners[0]
			if spawner.has_method("damage_tree"):
				spawner.damage_tree(collider, float(damage))


func apply_damage_to_enemy(enemy: Node, damage: int, hit_position: Vector3 = Vector3.ZERO) -> void:
	if not enemy or not enemy.has_method("take_damage"):
		return

	var final_damage := damage

	# Check if enemy is undead and apply bonus
	if spell_data and spell_data.bonus_vs_undead > 1.0:
		if enemy.has_method("is_undead") and enemy.is_undead():
			final_damage = int(damage * spell_data.bonus_vs_undead)

	# Apply status effects based on damage type
	_apply_status_effects(enemy)

	# Deal damage - pass hit position for headshot detection
	var damage_position: Vector3 = hit_position if hit_position != Vector3.ZERO else enemy.global_position + Vector3(0, 1.0, 0)
	enemy.take_damage(final_damage, owner_player, damage_position)

	# Lifesteal
	if spell_data and spell_data.lifesteal_percent > 0.0 and owner_player:
		var heal_amount := int(final_damage * spell_data.lifesteal_percent)
		if owner_player.has_method("heal"):
			owner_player.heal(heal_amount)

	# Manasteal
	if spell_data and spell_data.mana_steal_percent > 0.0:
		var mana_amount := int(final_damage * spell_data.mana_steal_percent)
		add_mana(mana_amount)


func _apply_status_effects(enemy: Node) -> void:
	if not spell_data or not enemy:
		return

	# Burn (Fire)
	if spell_data.burn_damage_per_sec > 0 and enemy.has_method("apply_burn"):
		enemy.apply_burn(spell_data.burn_damage_per_sec, spell_data.burn_duration)

	# Slow/Freeze (Ice)
	if spell_data.slow_percent > 0.0 and enemy.has_method("apply_slow"):
		enemy.apply_slow(spell_data.slow_percent, spell_data.slow_duration)

	if spell_data.freeze_chance > 0.0 and enemy.has_method("apply_freeze"):
		if randf() < spell_data.freeze_chance:
			enemy.apply_freeze(spell_data.freeze_duration)

	# Stun (Lightning)
	if spell_data.stun_chance > 0.0 and enemy.has_method("apply_stun"):
		if randf() < spell_data.stun_chance:
			enemy.apply_stun(spell_data.stun_duration)

	# Root (Nature)
	if spell_data.root_duration > 0.0 and enemy.has_method("apply_root"):
		enemy.apply_root(spell_data.root_duration)

	# DOT (Dark/Poison)
	if spell_data.dot_damage_per_sec > 0 and enemy.has_method("apply_dot"):
		enemy.apply_dot(spell_data.dot_damage_per_sec, spell_data.dot_duration)

	# Knockback
	if spell_data.knockback_force > 0.0 and enemy.has_method("apply_knockback"):
		var direction: Vector3 = (enemy.global_position - global_position).normalized()
		enemy.apply_knockback(direction * spell_data.knockback_force)


func get_enemies_in_radius(center: Vector3, radius: float) -> Array[Node]:
	var enemies: Array[Node] = []
	var space_state := get_world_3d().direct_space_state

	# Use sphere cast to find enemies
	var shape := SphereShape3D.new()
	shape.radius = radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = 0b100  # Enemy layer

	var results := space_state.intersect_shape(query)

	for result in results:
		var collider: Node = result.collider
		if collider and collider.has_method("take_damage"):
			enemies.append(collider)

	return enemies


func _on_cast_timer_timeout() -> void:
	_finish_cast()
	_play_cast_finish_effects()


func _on_cooldown_timer_timeout() -> void:
	is_on_cooldown = false
	can_cast = true
	cooldown_finished.emit()


func _on_mana_regen_timer_timeout() -> void:
	_regenerate_mana()


# Utility functions
func get_damage_type_name() -> String:
	return SpellRegistry.get_damage_type_name(damage_type)


func get_damage_type_color() -> Color:
	return SpellRegistry.get_damage_type_color(damage_type)


func get_cooldown_remaining() -> float:
	return cooldown_timer.time_left


func get_cast_progress() -> float:
	if not is_casting:
		return 0.0
	return 1.0 - (cast_timer.time_left / cast_time)


func set_max_mana(new_max: int) -> void:
	max_mana = new_max
	current_mana = min(current_mana, max_mana)
	mana_changed.emit(current_mana, max_mana)


func set_mana_regen(new_regen: float) -> void:
	mana_regen_per_sec = new_regen
