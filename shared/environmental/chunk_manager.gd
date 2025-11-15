extends Node3D

## Manages chunk-based spawning and culling of environmental objects
## Tracks player positions and loads/unloads chunks accordingly

signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)

@export var chunk_size: float = 32.0  ## Size of each chunk in world units
@export var load_radius: int = 4  ## How many chunks to load around players
@export var update_interval: float = 1.0  ## How often to update chunks (seconds)

# Component references
var spawner
var database
var voxel_world: Node3D

# Chunk tracking
var loaded_chunks: Dictionary = {}  # Vector2i -> Array of EnvironmentalObjects
var player_chunk_positions: Dictionary = {}  # int (peer_id) -> Vector2i
var modified_chunks: Dictionary = {}  # Vector2i -> bool (tracks which chunks have been edited)

# Update timer
var update_timer: float = 0.0

# Node container for spawned objects
var objects_container: Node3D

func _ready() -> void:
	# Create container for objects
	objects_container = Node3D.new()
	objects_container.name = "EnvironmentalObjects"
	add_child(objects_container)

	# Create database for persistent storage
	var ChunkDatabaseScript = load("res://shared/environmental/chunk_database.gd")
	database = ChunkDatabaseScript.new()
	database.name = "ChunkDatabase"
	add_child(database)

	# Create spawner
	var EnvironmentalSpawnerScript = load("res://shared/environmental/environmental_spawner.gd")
	spawner = EnvironmentalSpawnerScript.new()
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

	# Wait a frame to ensure database is fully ready
	await get_tree().process_frame

	# Initialize database for this world
	if database and is_instance_valid(database):
		database.initialize_for_world(voxel_world.world_name)

	# Sync settings with spawner
	if spawner and is_instance_valid(spawner):
		spawner.set_world_seed(voxel_world.world_seed)
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

	if not spawner or not is_instance_valid(spawner):
		push_error("[ChunkManager] Cannot load chunk - spawner not initialized!")
		return

	var objects: Array = []

	# Check if this chunk has been modified and saved
	if database and database.is_chunk_generated(chunk_pos):
		# Load from saved data
		var chunk_data = database.get_chunk(chunk_pos)
		objects = _load_chunk_from_saved_data(chunk_pos, chunk_data)
	else:
		# Generate procedurally
		objects = spawner.spawn_chunk_objects(chunk_pos, voxel_world, objects_container)

	loaded_chunks[chunk_pos] = objects

	# Assign object IDs and set initial distance for each object
	var chunk_center := _chunk_to_world(chunk_pos)
	var chunk_center_3d := Vector3(chunk_center.x, 0, chunk_center.y)
	var nearest_player_distance := _get_nearest_player_distance(chunk_center_3d)

	for i in objects.size():
		var obj = objects[i]
		if is_instance_valid(obj):
			# Assign object ID within chunk
			if obj.has_method("set_object_id"):
				obj.set_object_id(i)

			# Set initial distance for fade-in
			if obj.has_method("set_initial_distance"):
				obj.set_initial_distance(nearest_player_distance)

	chunk_loaded.emit(chunk_pos)

## Load chunk from saved database
func _load_chunk_from_saved_data(chunk_pos: Vector2i, chunk_data) -> Array:
	var objects: Array = []

	# Get active (not destroyed) objects
	var active_objects = chunk_data.get_active_objects()

	for obj_data in active_objects:
		# Spawn the object using spawner's method
		var obj = spawner.spawn_saved_object(obj_data, voxel_world, objects_container)
		if obj:
			obj.set_chunk_position(chunk_pos)
			objects.append(obj)

	return objects

## Unload a chunk and destroy its objects
func _unload_chunk(chunk_pos: Vector2i) -> void:
	if not loaded_chunks.has(chunk_pos):
		return

	var objects: Array = loaded_chunks[chunk_pos]

	# If chunk was modified, save it
	if modified_chunks.has(chunk_pos) and modified_chunks[chunk_pos] and database:
		_save_chunk_to_database(chunk_pos, objects)

	# Remove all objects
	for obj in objects:
		if is_instance_valid(obj):
			obj.queue_free()

	loaded_chunks.erase(chunk_pos)
	chunk_unloaded.emit(chunk_pos)

## Update visibility and LOD for all objects based on nearest player distance
func _update_object_visibility() -> void:
	if player_chunk_positions.is_empty():
		return

	# Get all player positions
	var player_positions: Array = []
	# We need to get actual player nodes - for now we'll skip this optimization
	# This will be called less frequently so it's okay

	# For each loaded chunk
	for chunk_pos in loaded_chunks.keys():
		var objects: Array = loaded_chunks[chunk_pos]

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

## Save a chunk to the database
func _save_chunk_to_database(chunk_pos: Vector2i, objects: Array) -> void:
	var chunk_data = database.get_chunk(chunk_pos)

	# Clear existing objects
	chunk_data.objects.clear()

	# Record current objects
	for obj in objects:
		if is_instance_valid(obj):
			var obj_type = "unknown"
			if obj.has_method("get_object_type"):
				obj_type = obj.get_object_type()

			chunk_data.add_object(obj_type, obj.global_position, obj.rotation, obj.scale)

	database.mark_chunk_generated(chunk_pos)
	database.save_chunk(chunk_pos)
	print("[ChunkManager] Saved modified chunk %s" % chunk_pos)

## Mark a chunk as modified (call this when a player interacts with objects)
func mark_chunk_modified(chunk_pos: Vector2i) -> void:
	modified_chunks[chunk_pos] = true

## Save all modified chunks to database (call on server shutdown)
func save_all_modified_chunks() -> void:
	if not database:
		return

	var saved_count := 0
	for chunk_pos in modified_chunks.keys():
		if modified_chunks[chunk_pos] and loaded_chunks.has(chunk_pos):
			var objects = loaded_chunks[chunk_pos]
			_save_chunk_to_database(chunk_pos, objects)
			saved_count += 1

	print("[ChunkManager] Saved %d modified chunks" % saved_count)

## Get stats for debugging
func get_stats() -> Dictionary:
	var total_objects := 0
	for objects in loaded_chunks.values():
		total_objects += objects.size()

	return {
		"loaded_chunks": loaded_chunks.size(),
		"total_objects": total_objects,
		"registered_players": player_chunk_positions.size(),
		"modified_chunks": modified_chunks.size()
	}
