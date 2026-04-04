extends StaticBody3D

## BuildableObject - Base class for player-constructed buildings
## Handles placement validation, health, and interaction

@export var object_name: String = "buildable"
@export var max_health: float = 100.0
@export var crafting_station_range: float = 20.0  # Range for workbench influence
@export var is_crafting_station: bool = false
@export var station_type: String = ""  # e.g., "workbench"

var current_health: float = 100.0
var is_placed: bool = false
var chunk_position: Vector2i
var object_id: int = -1
var is_preview: bool = false  # Ghost preview in build mode
var can_place: bool = true  # Whether current position is valid

# Building damage VFX
var _damage_shake_timer: float = 0.0
var _is_damage_shaking: bool = false
var _original_pos: Vector3 = Vector3.ZERO
var _health_bar: Node3D = null
const HEALTH_BAR_SCENE = preload("res://shared/health_bar_3d.tscn")

func _ready() -> void:
	current_health = max_health
	_original_pos = position

	if is_preview:
		_setup_preview_mode()
	else:
		add_to_group("player_buildings")

	if is_crafting_station and not station_type.is_empty():
		# PERFORMANCE: Add to group for efficient proximity lookup
		add_to_group("crafting_stations")
		if station_type == "workbench":
			add_to_group("workbenches")
		print("[BuildableObject] %s crafting station ready (range: %.1fm)" % [station_type, crafting_station_range])

func _process(delta: float) -> void:
	if _is_damage_shaking:
		_damage_shake_timer += delta
		var t = _damage_shake_timer / 0.2
		if t >= 1.0:
			_is_damage_shaking = false
			position = _original_pos
		else:
			position = _original_pos + Vector3(
				sin(_damage_shake_timer * 40.0) * 0.05 * (1.0 - t),
				0,
				cos(_damage_shake_timer * 30.0) * 0.03 * (1.0 - t)
			)

## Check if a position is within this crafting station's range
func is_position_in_range(pos: Vector3) -> bool:
	if not is_crafting_station:
		return false

	return global_position.distance_to(pos) <= crafting_station_range

## Take damage from enemies or other sources
func take_damage(damage: float) -> bool:
	current_health -= damage

	# Visual shake
	_is_damage_shaking = true
	_damage_shake_timer = 0.0

	# Tint red at low health
	_update_damage_tint()

	# Show health bar
	if not _health_bar:
		_health_bar = HEALTH_BAR_SCENE.instantiate()
		add_child(_health_bar)
		_health_bar.set_height_offset(2.0)
	if _health_bar:
		_health_bar.update_health(current_health, max_health)

	if current_health <= 0.0:
		_on_destroyed()
		return true

	return false

## Update tint based on health
func _update_damage_tint() -> void:
	var health_pct = current_health / max_health
	var tint: Color
	if health_pct < 0.25:
		tint = Color(1.0, 0.3, 0.3)
	elif health_pct < 0.5:
		tint = Color(1.0, 0.6, 0.4)
	else:
		tint = Color(1.0, 1.0, 1.0)

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if not mat and child.mesh:
				mat = child.mesh.surface_get_material(0)
			if mat and mat is StandardMaterial3D:
				var new_mat = mat.duplicate()
				new_mat.albedo_color = tint
				child.set_surface_override_material(0, new_mat)

## Called when destroyed
func _on_destroyed() -> void:
	print("[BuildableObject] %s destroyed!" % object_name)

	# Drop some materials back to nearby player
	var players = get_tree().get_nodes_in_group("local_player")
	if players.size() > 0:
		var player = players[0]
		if player.has_method("pickup_item"):
			player.pickup_item("wood", 1)

	queue_free()

## Set up as a ghost preview
func _setup_preview_mode() -> void:
	# Make semi-transparent
	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat:
				mat = mat.duplicate()
				if mat is StandardMaterial3D:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color.a = 0.5
				child.set_surface_override_material(0, mat)
			else:
				# No material - create a new transparent one
				mat = StandardMaterial3D.new()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.5
				child.set_surface_override_material(0, mat)

	# Disable collision during preview
	collision_layer = 0
	collision_mask = 0

## Update preview color based on placement validity
func set_preview_valid(valid: bool, is_snapped: bool = false) -> void:
	can_place = valid

	var color_tint: Color
	if not valid:
		color_tint = Color.RED
	elif is_snapped:
		color_tint = Color(0.3, 1.0, 0.3)  # Bright green when snapped
	else:
		color_tint = Color(0.6, 0.8, 0.6)  # Dimmer green for ground placement
	color_tint.a = 0.6 if is_snapped else 0.5

	for child in get_children():
		if child is MeshInstance3D:
			var mat = child.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				mat.albedo_color = color_tint
