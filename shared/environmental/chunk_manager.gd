extends Node3D
class_name ChunkManager

## Manages chunk-based spawning and culling of environmental objects
## Tracks player positions and loads/unloads chunks accordingly

signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)

@export var chunk_size: float = 32.0  ## Size of each chunk in world units
@export var load_radius: int = 4  ## How many chunks to load around players
@export var update_interval: float = 1.0  ## How often to update chunks (seconds)

# Component references
var spawner: EnvironmentalSpawner
var voxel_world: Node3D

# Chunk tracking
var loaded_chunks: Dictionary = {}  # Vector2i -> Array[EnvironmentalObject]
var player_chunk_positions: Dictionary = {}  # int (peer_id) -> Vector2i

# Update timer
var update_timer: float = 0.0

# Node container for spawned objects
var objects_container: Node3D

func _ready() -> void:
	# Create container for objects
	objects_container = Node3D.new()
	objects_container.name = "EnvironmentalObjects"
	add_child(objects_container)

	# Create spawner
	spawner = EnvironmentalSpawner.new()
	spawner.name = "EnvironmentalSpawner"
	add_child(spawner)

	print("[ChunkManager] Initialized with chunk_size=%d, load_radius=%d" % [chunk_size, load_radius])

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_chunks()
		_update_object_visibility()

## Initialize the chunk manager with voxel world reference
func initialize(voxel_world_ref: Node3D) -> void:
	voxel_world = voxel_world_ref

	# Sync settings with spawner
	spawner.set_world_seed(voxel_world.WORLD_SEED)
	spawner.set_chunk_size(chunk_size)

	print("[ChunkManager] Initialized with voxel world")

## Register a player's position for chunk loading
func register_player(peer_id: int, player_node: Node3D) -> void:
	var chunk_pos := _world_to_chunk(Vector2(player_node.global_position.x, player_node.global_position.z))
	player_chunk_positions[peer_id] = chunk_pos
	print("[ChunkManager] Registered player %d at chunk %s" % [peer_id, chunk_pos])

## Unregister a player (when they disconnect)
func unregister_player(peer_id: int) -> void:
	player_chunk_positions.erase(peer_id)
	print("[ChunkManager] Unregistered player %d" % peer_id)

## Update player position
func update_player_position(peer_id: int, position: Vector3) -> void:
	var chunk_pos := _world_to_chunk(Vector2(position.x, position.z))
	player_chunk_positions[peer_id] = chunk_pos

## Update which chunks should be loaded
func _update_chunks() -> void:
	if player_chunk_positions.is_empty():
		return

	# Collect all chunks that should be loaded
	var required_chunks: Dictionary = {}

	for peer_id in player_chunk_positions:
		var player_chunk: Vector2i = player_chunk_positions[peer_id]

		# Load chunks in radius around player
		for x in range(-load_radius, load_radius + 1):
			for z in range(-load_radius, load_radius + 1):
				var chunk_pos := Vector2i(player_chunk.x + x, player_chunk.y + z)
				required_chunks[chunk_pos] = true

	# Unload chunks that are no longer needed
	var chunks_to_unload: Array[Vector2i] = []
	for chunk_pos in loaded_chunks.keys():
		if not required_chunks.has(chunk_pos):
			chunks_to_unload.append(chunk_pos)

	for chunk_pos in chunks_to_unload:
		_unload_chunk(chunk_pos)

	# Load new chunks
	for chunk_pos in required_chunks.keys():
		if not loaded_chunks.has(chunk_pos):
			_load_chunk(chunk_pos)

## Load a chunk and spawn its objects
func _load_chunk(chunk_pos: Vector2i) -> void:
	if not voxel_world:
		push_error("[ChunkManager] Cannot load chunk - voxel_world not initialized!")
		return

	# Spawn objects for this chunk
	var objects := spawner.spawn_chunk_objects(chunk_pos, voxel_world, objects_container)

	# Store in loaded chunks
	loaded_chunks[chunk_pos] = objects

	chunk_loaded.emit(chunk_pos)

	if objects.size() > 0:
		print("[ChunkManager] Loaded chunk %s with %d objects" % [chunk_pos, objects.size()])

## Unload a chunk and destroy its objects
func _unload_chunk(chunk_pos: Vector2i) -> void:
	if not loaded_chunks.has(chunk_pos):
		return

	var objects: Array[EnvironmentalObject] = loaded_chunks[chunk_pos]

	# Remove all objects
	for obj in objects:
		if is_instance_valid(obj):
			obj.queue_free()

	loaded_chunks.erase(chunk_pos)
	chunk_unloaded.emit(chunk_pos)

	if objects.size() > 0:
		print("[ChunkManager] Unloaded chunk %s (%d objects)" % [chunk_pos, objects.size()])

## Update visibility and LOD for all objects based on nearest player distance
func _update_object_visibility() -> void:
	if player_chunk_positions.is_empty():
		return

	# Get all player positions
	var player_positions: Array[Vector3] = []
	# We need to get actual player nodes - for now we'll skip this optimization
	# This will be called less frequently so it's okay

	# For each loaded chunk
	for chunk_pos in loaded_chunks.keys():
		var objects: Array[EnvironmentalObject] = loaded_chunks[chunk_pos]

		# Update each object
		for obj in objects:
			if not is_instance_valid(obj):
				continue

			# Find nearest player distance
			var nearest_distance := _get_nearest_player_distance(obj.global_position)

			# Update object visibility/LOD
			obj.update_visibility(nearest_distance)

## Get distance to nearest player from a position
func _get_nearest_player_distance(pos: Vector3) -> float:
	var nearest := INF

	# This is a simplified version - in reality we'd track actual player node references
	# For now, estimate based on chunk positions
	for peer_id in player_chunk_positions:
		var chunk_pos: Vector2i = player_chunk_positions[peer_id]
		var chunk_world_pos := Vector2(chunk_pos.x * chunk_size + chunk_size * 0.5,
										chunk_pos.y * chunk_size + chunk_size * 0.5)
		var player_estimated_pos := Vector3(chunk_world_pos.x, pos.y, chunk_world_pos.y)
		var distance := pos.distance_to(player_estimated_pos)
		nearest = min(nearest, distance)

	return nearest

## Convert world position to chunk coordinate
func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / chunk_size),
		floori(world_pos.y / chunk_size)
	)

## Convert chunk coordinate to world position (center of chunk)
func _chunk_to_world(chunk_pos: Vector2i) -> Vector2:
	return Vector2(
		chunk_pos.x * chunk_size + chunk_size * 0.5,
		chunk_pos.y * chunk_size + chunk_size * 0.5
	)

## Get stats for debugging
func get_stats() -> Dictionary:
	var total_objects := 0
	for objects in loaded_chunks.values():
		total_objects += objects.size()

	return {
		"loaded_chunks": loaded_chunks.size(),
		"total_objects": total_objects,
		"registered_players": player_chunk_positions.size()
	}
