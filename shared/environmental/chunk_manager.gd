extends Node3D

## Manages chunk-based spawning and culling of environmental objects
## Uses MultiMesh for efficient batched rendering of all object types

signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)

@export var chunk_size: float = 32.0  ## Size of each chunk in world units
@export var load_radius: int = 4  ## Default chunks to load around players (used if player hasn't set preference)
@export var update_interval: float = 1.0  ## How often to update chunks (seconds)

# Component references
var spawner
var database
var voxel_world: Node3D

# Chunk tracking - now stores MultimeshChunk instead of Array
var loaded_chunks: Dictionary = {}  # Vector2i -> MultimeshChunk
var player_chunk_positions: Dictionary = {}  # int (peer_id) -> Vector2i
var player_load_radii: Dictionary = {}  # int (peer_id) -> int (per-player render distance)
var modified_chunks: Dictionary = {}  # Vector2i -> bool (tracks which chunks have been edited)

# Update timer
var update_timer: float = 0.0

# Node container for spawned objects
var objects_container: Node3D

# MultimeshChunk script - loaded dynamically to avoid circular reference issues
var MultimeshChunkScript

func _ready() -> void:
	# Load MultimeshChunk script
	MultimeshChunkScript = load("res://shared/environmental/multimesh_chunk.gd")

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

	print("[ChunkManager] Initialized with MultiMesh system, chunk_size=%d, load_radius=%d" % [chunk_size, load_radius])

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_chunks()

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

	print("[ChunkManager] Initialized with voxel world (MultiMesh mode)")

## Register a player's position for chunk loading
func register_player(peer_id: int, player_node: Node3D) -> void:
	var chunk_pos := _world_to_chunk(Vector2(player_node.global_position.x, player_node.global_position.z))
	player_chunk_positions[peer_id] = chunk_pos
	print("[ChunkManager] Registered player %d at chunk %s" % [peer_id, chunk_pos])

## Unregister a player (when they disconnect)
func unregister_player(peer_id: int) -> void:
	player_chunk_positions.erase(peer_id)
	player_load_radii.erase(peer_id)
	print("[ChunkManager] Unregistered player %d" % peer_id)

## Set a player's preferred object render distance
func set_player_load_radius(peer_id: int, radius: int) -> void:
	player_load_radii[peer_id] = radius
	print("[ChunkManager] Set player %d load radius to %d" % [peer_id, radius])

## Get a player's load radius (or default if not set)
func get_player_load_radius(peer_id: int) -> int:
	return player_load_radii.get(peer_id, load_radius)

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
		var player_radius: int = get_player_load_radius(peer_id)

		# Load chunks in radius around player (using their personal setting)
		for x in range(-player_radius, player_radius + 1):
			for z in range(-player_radius, player_radius + 1):
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

## Load a chunk using MultiMesh
func _load_chunk(chunk_pos: Vector2i) -> void:
	if not voxel_world:
		push_error("[ChunkManager] Cannot load chunk - voxel_world not initialized!")
		return

	if not spawner or not is_instance_valid(spawner):
		push_error("[ChunkManager] Cannot load chunk - spawner not initialized!")
		return

	# Create MultimeshChunk
	var mm_chunk = MultimeshChunkScript.new()
	mm_chunk.set_chunk_position(chunk_pos)
	objects_container.add_child(mm_chunk)

	# Connect destruction signal
	mm_chunk.instance_destroyed.connect(_on_instance_destroyed)

	# Check if this chunk has been modified and saved
	if database and database.is_chunk_generated(chunk_pos):
		# Load from saved data
		_load_chunk_from_saved_data(chunk_pos, mm_chunk)
	else:
		# Generate procedurally using MultiMesh
		var transforms_by_type: Dictionary = spawner.generate_chunk_transforms(chunk_pos, voxel_world)

		for object_type in transforms_by_type.keys():
			# Skip grass - handled separately with dense decoration system
			if object_type == "grass":
				continue
			var transforms: Array[Transform3D] = []
			for t in transforms_by_type[object_type]:
				transforms.append(t)
			mm_chunk.add_instances(object_type, transforms)

	# Grass is generated client-side only for performance
	# Server doesn't need grass (no collision, no persistence, client-only decoration)

	loaded_chunks[chunk_pos] = mm_chunk
	chunk_loaded.emit(chunk_pos)

## Load chunk from saved database
func _load_chunk_from_saved_data(chunk_pos: Vector2i, mm_chunk) -> void:
	var chunk_data = database.get_chunk(chunk_pos)

	# Group saved objects by type and build transforms
	var transforms_by_type: Dictionary = {}
	var destroyed_by_type: Dictionary = {}

	var active_objects = chunk_data.get_active_objects()

	for obj_data in active_objects:
		var obj_type: String = obj_data.object_type
		if not transforms_by_type.has(obj_type):
			transforms_by_type[obj_type] = []

		# Build transform from saved data
		var basis := Basis.from_euler(obj_data.rotation) * Basis.from_scale(obj_data.scale)
		var transform := Transform3D(basis, obj_data.position)
		transforms_by_type[obj_type].append(transform)

	# Add all instances to chunk
	for object_type in transforms_by_type.keys():
		var transforms: Array[Transform3D] = []
		for t in transforms_by_type[object_type]:
			transforms.append(t)
		mm_chunk.add_instances(object_type, transforms)

	# Mark destroyed instances
	var destroyed_objects = chunk_data.get_destroyed_objects()
	for obj_data in destroyed_objects:
		var obj_type: String = obj_data.object_type
		if not destroyed_by_type.has(obj_type):
			destroyed_by_type[obj_type] = []
		destroyed_by_type[obj_type].append(obj_data.object_id)

	for object_type in destroyed_by_type.keys():
		for idx in destroyed_by_type[object_type]:
			mm_chunk.mark_destroyed(object_type, idx)

## Unload a chunk
func _unload_chunk(chunk_pos: Vector2i) -> void:
	if not loaded_chunks.has(chunk_pos):
		return

	var mm_chunk = loaded_chunks[chunk_pos]

	# If chunk was modified, save it
	if modified_chunks.has(chunk_pos) and modified_chunks[chunk_pos] and database:
		_save_chunk_to_database(chunk_pos, mm_chunk)

	# Cleanup and remove
	mm_chunk.cleanup()
	mm_chunk.queue_free()

	loaded_chunks.erase(chunk_pos)
	chunk_unloaded.emit(chunk_pos)

## Handle instance destruction
func _on_instance_destroyed(chunk_pos: Vector2i, object_type: String, instance_index: int, resource_drops: Dictionary) -> void:
	mark_chunk_modified(chunk_pos)
	# Could emit signal here for resource drop spawning
	print("[ChunkManager] Instance destroyed: %s #%d at chunk %s, drops: %s" % [object_type, instance_index, chunk_pos, resource_drops])

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
func _save_chunk_to_database(chunk_pos: Vector2i, mm_chunk) -> void:
	var chunk_data = database.get_chunk(chunk_pos)

	# Clear existing objects
	chunk_data.objects.clear()

	# Record current objects with their states
	for object_type in mm_chunk.instances.keys():
		var inst_array: Array = mm_chunk.instances[object_type]
		var transform_array: Array = mm_chunk.instance_transforms[object_type]

		for i in inst_array.size():
			var inst = inst_array[i]
			var transform: Transform3D = transform_array[i]

			chunk_data.add_object(
				object_type,
				transform.origin,
				transform.basis.get_euler(),
				transform.basis.get_scale()
			)

			# Mark destroyed in database
			if inst.destroyed:
				chunk_data.mark_object_destroyed(i)

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
			var mm_chunk = loaded_chunks[chunk_pos]
			_save_chunk_to_database(chunk_pos, mm_chunk)
			saved_count += 1

	print("[ChunkManager] Saved %d modified chunks" % saved_count)

## Apply damage to object at world position
func damage_at_position(world_pos: Vector3, damage: float) -> Dictionary:
	var chunk_pos := _world_to_chunk(Vector2(world_pos.x, world_pos.z))

	if not loaded_chunks.has(chunk_pos):
		return {"hit": false}

	var mm_chunk = loaded_chunks[chunk_pos]
	var result = mm_chunk.get_instance_at_position(world_pos)

	if result.index >= 0:
		var destroyed = mm_chunk.apply_damage(result.object_type, result.index, damage)
		return {
			"hit": true,
			"object_type": result.object_type,
			"destroyed": destroyed,
			"chunk_pos": chunk_pos
		}

	return {"hit": false}

## Get stats for debugging
func get_stats() -> Dictionary:
	var total_instances := 0
	var total_multimeshes := 0

	for chunk_pos in loaded_chunks.keys():
		var mm_chunk = loaded_chunks[chunk_pos]
		total_instances += mm_chunk.get_total_instance_count()
		total_multimeshes += mm_chunk.mesh_containers.size()

	return {
		"loaded_chunks": loaded_chunks.size(),
		"total_instances": total_instances,
		"total_multimeshes": total_multimeshes,
		"registered_players": player_chunk_positions.size(),
		"modified_chunks": modified_chunks.size()
	}
