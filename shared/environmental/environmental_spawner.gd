extends Node

## Handles deterministic spawning of environmental objects based on terrain
## Uses world seed + chunk coordinates for consistent, reproducible placement

## Spawn configuration for different object types
class SpawnConfig:
	var scene: PackedScene
	var density: float = 0.1  # 0.0 to 1.0
	var min_height: float = -10.0
	var max_height: float = 60.0
	var min_slope: float = 0.0  # degrees
	var max_slope: float = 35.0  # degrees
	var allowed_biomes: Array[String] = []
	var scale_variation: Vector2 = Vector2(0.8, 1.2)
	var rotation_variation: bool = true

# Preloaded scenes
var tree_scene: PackedScene
var rock_scene: PackedScene
var grass_scene: PackedScene
var mushroom_tree_scene: PackedScene
var giant_mushroom_scene: PackedScene
var glowing_mushroom_scene: PackedScene
var spore_cluster_scene: PackedScene

# Spawn configurations
var spawn_configs: Dictionary = {}

# World settings
var world_seed: int = 42
var chunk_size: float = 32.0  # Chunk size in world units

func _ready() -> void:
	# Load scenes
	tree_scene = load("res://shared/environmental/tree.tscn")
	rock_scene = load("res://shared/environmental/rock.tscn")
	grass_scene = load("res://shared/environmental/grass_clump.tscn")
	mushroom_tree_scene = load("res://shared/environmental/mushroom_tree.tscn")
	giant_mushroom_scene = load("res://shared/environmental/giant_mushroom.tscn")
	glowing_mushroom_scene = load("res://shared/environmental/glowing_mushroom.tscn")
	spore_cluster_scene = load("res://shared/environmental/spore_cluster.tscn")

	# Setup spawn configurations
	_setup_spawn_configs()

func _setup_spawn_configs() -> void:
	# Trees - spawn in valleys only (dark_forest uses dark_pine instead)
	var tree_config := SpawnConfig.new()
	tree_config.scene = tree_scene
	tree_config.density = 0.15
	tree_config.min_height = -5.0
	tree_config.max_height = 30.0
	tree_config.max_slope = 35.0
	tree_config.allowed_biomes = ["valley"]
	spawn_configs["tree"] = tree_config

	# Rocks - spawn everywhere
	var rock_config := SpawnConfig.new()
	rock_config.scene = rock_scene
	rock_config.density = 0.08
	rock_config.min_height = -10.0
	rock_config.max_height = 60.0
	rock_config.max_slope = 60.0
	rock_config.allowed_biomes = ["valley", "dark_forest", "swamp", "mountain", "desert"]
	spawn_configs["rock"] = rock_config

	# Grass - dense in valleys only (dark_forest uses glowing mushrooms instead)
	var grass_config := SpawnConfig.new()
	grass_config.scene = grass_scene
	grass_config.density = 0.4
	grass_config.min_height = -5.0
	grass_config.max_height = 25.0
	grass_config.max_slope = 25.0
	grass_config.allowed_biomes = ["valley"]
	spawn_configs["grass"] = grass_config

	# Mushroom Trees - medium mushroom trees for dark_forest biome
	var mushroom_tree_config := SpawnConfig.new()
	mushroom_tree_config.scene = mushroom_tree_scene
	mushroom_tree_config.density = 0.6
	mushroom_tree_config.min_height = -5.0
	mushroom_tree_config.max_height = 35.0
	mushroom_tree_config.max_slope = 35.0
	mushroom_tree_config.allowed_biomes = ["dark_forest"]
	mushroom_tree_config.scale_variation = Vector2(0.7, 1.4)
	spawn_configs["mushroom_tree"] = mushroom_tree_config

	# Glowing Mushrooms - scattered fungi for dark_forest biome (high density for bioluminescent atmosphere)
	var mushroom_config := SpawnConfig.new()
	mushroom_config.scene = glowing_mushroom_scene
	mushroom_config.density = 0.65
	mushroom_config.min_height = -5.0
	mushroom_config.max_height = 30.0
	mushroom_config.max_slope = 40.0
	mushroom_config.allowed_biomes = ["dark_forest"]
	mushroom_config.scale_variation = Vector2(0.6, 1.5)
	spawn_configs["glowing_mushroom"] = mushroom_config

	# Spore Clusters - floating glowing spore clusters for dark_forest biome
	var spore_config := SpawnConfig.new()
	spore_config.scene = spore_cluster_scene
	spore_config.density = 0.35
	spore_config.min_height = -5.0
	spore_config.max_height = 30.0
	spore_config.max_slope = 45.0
	spore_config.allowed_biomes = ["dark_forest"]
	spore_config.scale_variation = Vector2(0.7, 1.4)
	spawn_configs["spore_cluster"] = spore_config

	# Giant Mushrooms - massive mushroom trees forming upper canopy for dark_forest biome
	var giant_mushroom_config := SpawnConfig.new()
	giant_mushroom_config.scene = giant_mushroom_scene
	giant_mushroom_config.density = 0.4
	giant_mushroom_config.min_height = -5.0
	giant_mushroom_config.max_height = 35.0
	giant_mushroom_config.max_slope = 30.0
	giant_mushroom_config.allowed_biomes = ["dark_forest"]
	giant_mushroom_config.scale_variation = Vector2(0.8, 1.6)
	spawn_configs["giant_mushroom"] = giant_mushroom_config

## Spawn objects for a given chunk (procedural generation)
## Returns array of spawned EnvironmentalObject instances
func spawn_chunk_objects(chunk_pos: Vector2i, voxel_world: Node3D, parent: Node3D) -> Array:
	var spawned_objects: Array = []

	# Create deterministic RNG for this chunk
	var rng := RandomNumberGenerator.new()
	var chunk_seed := _get_chunk_seed(chunk_pos)
	rng.seed = chunk_seed

	# Calculate chunk world bounds
	var chunk_world_pos := Vector2(chunk_pos.x * chunk_size, chunk_pos.y * chunk_size)

	# Attempt to spawn each object type
	for object_type in spawn_configs.keys():
		var config: SpawnConfig = spawn_configs[object_type]

		# Determine how many objects to try spawning in this chunk
		var attempts := int(chunk_size * chunk_size * config.density / 10.0)

		for i in attempts:
			# Generate random position within chunk
			var local_x := rng.randf_range(0, chunk_size)
			var local_z := rng.randf_range(0, chunk_size)
			var world_pos := Vector2(chunk_world_pos.x + local_x, chunk_world_pos.y + local_z)

			# Check if we should spawn here
			if _should_spawn_at_position(world_pos, config, voxel_world, rng):
				var obj = _spawn_object(config, world_pos, voxel_world, parent, rng, object_type)
				if obj:
					obj.set_chunk_position(chunk_pos)
					spawned_objects.append(obj)

	return spawned_objects

## Spawn an object from saved data
func spawn_saved_object(obj_data, voxel_world: Node3D, parent: Node3D):
	# Get the appropriate scene for this object type
	var config: SpawnConfig = spawn_configs.get(obj_data.object_type)
	if not config:
		push_error("[EnvironmentalSpawner] Unknown object type: %s" % obj_data.object_type)
		return null

	# Instance the scene
	var obj = config.scene.instantiate()
	if not obj:
		push_error("[EnvironmentalSpawner] Failed to instantiate object!")
		return null

	# Set the original scale before adding to tree (so fade-in can use it)
	if obj.has_method("set_target_scale"):
		obj.set_target_scale(obj_data.scale)

	# Set object type
	if obj.has_method("set_object_type"):
		obj.set_object_type(obj_data.object_type)

	# Add to scene
	parent.add_child(obj)

	# Restore saved transform
	obj.global_position = obj_data.position
	obj.rotation = obj_data.rotation
	# Note: scale will be set by fade-in animation using target_scale

	return obj

## Check if an object should spawn at the given position
func _should_spawn_at_position(xz_pos: Vector2, config: SpawnConfig, voxel_world: Node3D, rng: RandomNumberGenerator) -> bool:
	# Get terrain height at this position
	var height: float = voxel_world.get_terrain_height_at(xz_pos)

	# Check height constraints
	if height < config.min_height or height > config.max_height:
		return false

	# Check biome constraints
	if config.allowed_biomes.size() > 0:
		var biome: String = voxel_world.get_biome_at(xz_pos)
		if not biome in config.allowed_biomes:
			return false

	# Check slope (simplified - would need proper normal calculation)
	# For now, just use height variation in a small radius
	var slope_check: float = _estimate_slope_at(xz_pos, voxel_world)
	if slope_check < config.min_slope or slope_check > config.max_slope:
		return false

	# Random density check
	if rng.randf() > config.density:
		return false

	return true

## Estimate slope at position (simplified)
func _estimate_slope_at(xz_pos: Vector2, voxel_world: Node3D) -> float:
	var center_height: float = voxel_world.get_terrain_height_at(xz_pos)
	var offset: float = 2.0

	# Sample height at nearby points
	var heights: Array = [
		voxel_world.get_terrain_height_at(xz_pos + Vector2(offset, 0)),
		voxel_world.get_terrain_height_at(xz_pos + Vector2(-offset, 0)),
		voxel_world.get_terrain_height_at(xz_pos + Vector2(0, offset)),
		voxel_world.get_terrain_height_at(xz_pos + Vector2(0, -offset))
	]

	# Find max height difference
	var max_diff: float = 0.0
	for h in heights:
		var diff: float = abs(h - center_height)
		max_diff = max(max_diff, diff)

	# Convert to approximate slope in degrees
	return rad_to_deg(atan(max_diff / offset))

## Actually spawn an object at the given position
func _spawn_object(config: SpawnConfig, xz_pos: Vector2, voxel_world: Node3D, parent: Node3D, rng: RandomNumberGenerator, object_type: String):
	# Find surface height
	var surface_pos: Vector3 = voxel_world.find_surface_position(xz_pos, 100.0, 200.0)

	# Instance the scene
	var obj := config.scene.instantiate()
	if not obj:
		push_error("[EnvironmentalSpawner] Failed to instantiate object!")
		return null

	# Add to scene first (required for global_position to work)
	parent.add_child(obj)

	# Set position
	obj.global_position = surface_pos

	# Apply random rotation (Y axis only for trees/rocks)
	var rotation_y: float = 0.0
	if config.rotation_variation:
		rotation_y = rng.randf_range(0, TAU)
		obj.rotation.y = rotation_y

	# Apply random scale with variation for trees
	var scale_factor := rng.randf_range(config.scale_variation.x, config.scale_variation.y)
	if object_type == "mushroom_tree" or object_type == "giant_mushroom" or object_type == "tree":
		# Non-uniform scale for mushroom trees: vary width and height independently
		var width_factor := scale_factor * rng.randf_range(0.8, 1.2)
		var height_factor := scale_factor * rng.randf_range(0.85, 1.4)
		obj.scale = Vector3(width_factor, height_factor, width_factor)
	else:
		obj.scale = Vector3.ONE * scale_factor

	# Store metadata on object for later reference
	if obj.has_method("set_object_type"):
		obj.set_object_type(object_type)

	# Configure health and resource drops based on type
	_configure_object_properties(obj, object_type)

	return obj

## Configure object-specific properties (health, resource drops)
func _configure_object_properties(obj: Node3D, object_type: String) -> void:
	match object_type:
		"tree":
			if "max_health" in obj:
				obj.max_health = 100.0
				obj.current_health = 100.0
			if "resource_drops" in obj:
				obj.resource_drops = {"wood": 3}
		"rock":
			if "max_health" in obj:
				obj.max_health = 150.0
				obj.current_health = 150.0
			if "resource_drops" in obj:
				obj.resource_drops = {"stone": 5}
		"grass":
			if "max_health" in obj:
				obj.max_health = 10.0
				obj.current_health = 10.0
			if "resource_drops" in obj:
				obj.resource_drops = {}  # Grass drops nothing
		"mushroom_tree":
			if "max_health" in obj:
				obj.max_health = 100.0
				obj.current_health = 100.0
			if "resource_drops" in obj:
				obj.resource_drops = {"fungal_wood": 4}
		"glowing_mushroom":
			if "max_health" in obj:
				obj.max_health = 30.0
				obj.current_health = 30.0
			if "resource_drops" in obj:
				obj.resource_drops = {"glowing_spore": 2}
		"giant_mushroom":
			if "max_health" in obj:
				obj.max_health = 180.0
				obj.current_health = 180.0
			if "resource_drops" in obj:
				obj.resource_drops = {"fungal_wood": 8}
		"spore_cluster":
			if "max_health" in obj:
				obj.max_health = 25.0
				obj.current_health = 25.0
			if "resource_drops" in obj:
				obj.resource_drops = {"glowing_spore": 3}

## Generate deterministic seed for a chunk
func _get_chunk_seed(chunk_pos: Vector2i) -> int:
	# Combine world seed with chunk coordinates
	var hash_value := world_seed
	hash_value = hash_value * 31 + chunk_pos.x
	hash_value = hash_value * 31 + chunk_pos.y
	return hash_value

## Set the world seed (should match VoxelWorld seed)
func set_world_seed(seed_value: int) -> void:
	world_seed = seed_value

## Set chunk size (should match chunk manager)
func set_chunk_size(size: float) -> void:
	chunk_size = size
