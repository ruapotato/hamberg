extends Node3D

## Manages volumetric fog settings to create edge fade at render distance
## Uses global volumetric fog with tuned parameters

const CHUNK_SIZE: float = 32.0

var fog_enabled: bool = true

func _ready() -> void:
	print("[FogWallManager] Ready - managing volumetric fog")
	# Apply initial fog settings after environment is ready
	call_deferred("_apply_initial_settings")

func _apply_initial_settings() -> void:
	await get_tree().create_timer(1.5).timeout
	set_render_distance(4)  # Default 4 chunks

func set_render_distance(object_distance: int) -> void:
	var env = _get_environment()
	if not env:
		print("[FogWallManager] No environment found")
		return

	if not fog_enabled:
		return

	var max_distance = object_distance * CHUNK_SIZE

	# Set fog length to 80% of render distance - fog will be thick at the edge
	env.volumetric_fog_length = max_distance * 0.8
	# Low density so fog only becomes visible at the far edge
	env.volumetric_fog_density = 0.008

	print("[FogWallManager] Fog length: %.0f (objects at %.0f)" % [max_distance * 0.8, max_distance])

func set_fog_enabled(enabled: bool) -> void:
	fog_enabled = enabled
	var env = _get_environment()
	if env:
		env.volumetric_fog_enabled = enabled
		print("[FogWallManager] Fog enabled: %s" % enabled)

func set_fog_color(color: Color) -> void:
	var env = _get_environment()
	if env:
		env.volumetric_fog_albedo = color
		env.volumetric_fog_emission = color

func _get_environment() -> Environment:
	var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
	for tw in terrain_worlds:
		var world_env = tw.get_node_or_null("WorldEnvironment")
		if world_env and world_env.environment:
			return world_env.environment
	return null
