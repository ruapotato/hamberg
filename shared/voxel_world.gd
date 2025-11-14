extends Node3D

## VoxelWorld - Manages procedural voxel terrain generation
## Handles both server-side authority and client-side rendering

@onready var terrain: VoxelLodTerrain = $VoxelLodTerrain
@onready var multiplayer_sync: VoxelTerrainMultiplayerSynchronizer = $VoxelLodTerrain/VoxelTerrainMultiplayerSynchronizer

# World generation settings
const WORLD_SEED: int = 42  # TODO: Make this configurable
const SEA_LEVEL: float = 0.0
const TERRAIN_HEIGHT: float = 60.0
const TERRAIN_SCALE: float = 0.01  # Controls how "zoomed out" the noise is

# Biome heights (will be used for multi-biome generation later)
const MEADOW_HEIGHT: float = 5.0
const FOREST_HEIGHT: float = 20.0
const MOUNTAIN_HEIGHT: float = 50.0

var is_server: bool = false
var is_initialized: bool = false

func _ready() -> void:
	print("[VoxelWorld] Initializing voxel terrain system...")

	# Wait a frame to ensure multiplayer is fully initialized
	await get_tree().process_frame

	# Determine if we're server or client
	is_server = multiplayer.is_server()

	# Configure terrain based on role
	if is_server:
		_setup_server()
	else:
		_setup_client()

	# Setup the generator (both server and client need this)
	_setup_generator()

	is_initialized = true
	print("[VoxelWorld] Voxel terrain initialized (Server: %s)" % is_server)

func _setup_server() -> void:
	print("[VoxelWorld] Configuring server-side terrain...")

	# Server needs full terrain processing
	terrain.process_mode = Node.PROCESS_MODE_INHERIT

	# VoxelLodTerrain collision is configured in the scene file
	# collision_layer and collision_mask are set there

	# Server generates and manages the terrain
	# Multiplayer synchronizer will handle sending data to clients

func _setup_client() -> void:
	print("[VoxelWorld] Configuring client-side terrain...")

	# Client needs visual rendering
	terrain.process_mode = Node.PROCESS_MODE_INHERIT

	# Collision on client (for local physics prediction)
	# collision_layer and collision_mask are set in scene file

	# Client will receive terrain data from server via multiplayer sync

func _setup_generator() -> void:
	# Create custom biome-based generator (Valheim-style)
	print("[VoxelWorld] Setting up biome generator...")

	# Load the biome generator script
	var BiomeGenerator := preload("res://shared/biome_generator.gd")
	var generator := BiomeGenerator.new()

	# Assign to terrain
	terrain.generator = generator

	print("[VoxelWorld] Generator configured: Biome-based (distance + height)")

## Get terrain height at a given XZ position (approximate)
## Useful for spawning players/objects on the surface
func get_terrain_height_at(xz_pos: Vector2) -> float:
	# This is an approximation - for precise results, use raycasting
	var generator: VoxelGenerator = terrain.generator

	# Check if it's our BiomeGenerator
	if generator.has_method("get_height_at_position"):
		return generator.get_height_at_position(xz_pos)
	elif generator is VoxelGeneratorNoise2D:
		var gen := generator as VoxelGeneratorNoise2D
		if gen.noise:
			var noise_value = gen.noise.get_noise_2d(xz_pos.x, xz_pos.y)
			# Remap from [-1, 1] to terrain height range
			return gen.height_start + (noise_value * 0.5 + 0.5) * gen.height_range
	elif generator is VoxelGeneratorFlat:
		var gen := generator as VoxelGeneratorFlat
		return gen.height

	return 0.0  # Fallback to sea level

## Find the actual surface position at XZ coordinates (more precise)
## Uses voxel data to find the surface
func find_surface_position(xz_pos: Vector2, search_start_y: float = 100.0, search_range: float = 200.0) -> Vector3:
	# Raycast from above to find the surface
	var start_pos := Vector3(xz_pos.x, search_start_y, xz_pos.y)
	var end_pos := Vector3(xz_pos.x, search_start_y - search_range, xz_pos.y)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collision_mask = 1  # World layer

	var result := space_state.intersect_ray(query)
	if result:
		return result.position

	# Fallback to height estimation
	var estimated_height := get_terrain_height_at(xz_pos)
	return Vector3(xz_pos.x, estimated_height, xz_pos.y)

## Get biome type at position
func get_biome_at(xz_pos: Vector2) -> String:
	var generator: VoxelGenerator = terrain.generator

	# Use BiomeGenerator if available
	if generator.has_method("get_biome_at_position"):
		return generator.get_biome_at_position(xz_pos)

	# Fallback to height-based
	var height := get_terrain_height_at(xz_pos)
	var relative_height := height - SEA_LEVEL

	if relative_height < MEADOW_HEIGHT:
		return "meadow"
	elif relative_height < FOREST_HEIGHT:
		return "forest"
	else:
		return "mountain"

## Enable/disable terrain processing (useful for optimization)
func set_terrain_active(active: bool) -> void:
	terrain.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

## Save modified terrain blocks (call this when player saves)
func save_terrain() -> void:
	if terrain.stream:
		terrain.save_modified_blocks()
		print("[VoxelWorld] Saved modified terrain blocks")
