class_name TerrainMeshManager
extends RefCounted

## TerrainMeshManager - Handles threaded mesh generation and LOD

var terrain_world: Node3D

# Threading for mesh generation
var mesh_updates_in_progress: Dictionary = {}  # chunk_key -> task_id
var completed_mesh_results: Array = []
var mesh_result_mutex: Mutex = Mutex.new()
const MAX_CONCURRENT_MESH_TASKS: int = 4

# LOD distances (in chunks from player)
const LOD_DISTANCES: Array = [3, 6, 10]  # LOD 0 within 3 chunks, LOD 1 within 6, etc.

func _init(tw: Node3D) -> void:
	terrain_world = tw

# =============================================================================
# LOD MANAGEMENT
# =============================================================================

## Check if any chunks need LOD updates (when player moves closer)
func check_lod_updates(player_pos: Vector3) -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var player_chunk := ChunkDataClass.world_to_chunk_coords(player_pos)

	# Only check chunks that are loaded and not currently being processed
	for chunk_key in terrain_world.chunks:
		if mesh_updates_in_progress.has(chunk_key):
			continue
		if terrain_world.pending_mesh_updates.has(chunk_key):
			continue

		var chunk = terrain_world.chunks[chunk_key]
		var current_lod: int = terrain_world.chunk_lod_levels.get(chunk_key, -1)
		var desired_lod: int = get_chunk_lod_level(chunk.chunk_x, chunk.chunk_z)

		# Only upgrade LOD (reduce level number) when player gets closer
		if current_lod > desired_lod or current_lod == -1:
			chunk.is_dirty = true
			terrain_world.pending_mesh_updates.append(chunk_key)

## Get the LOD level for a chunk based on distance from any tracked player
func get_chunk_lod_level(cx: int, cz: int) -> int:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var min_dist_sq: float = INF

	for peer_id in terrain_world.tracked_players:
		var player = terrain_world.tracked_players[peer_id]
		if is_instance_valid(player):
			var player_chunk := ChunkDataClass.world_to_chunk_coords(player.global_position)
			var dx: int = cx - player_chunk.x
			var dz: int = cz - player_chunk.y
			var dist_sq: float = dx * dx + dz * dz
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq

	var dist: float = sqrt(min_dist_sq)

	# Determine LOD level based on distance
	for i in LOD_DISTANCES.size():
		if dist <= LOD_DISTANCES[i]:
			return i
	return LOD_DISTANCES.size()  # Furthest LOD

# =============================================================================
# THREADED MESH GENERATION
# =============================================================================

## Start threaded mesh generation for pending chunks
func start_threaded_mesh_updates() -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass

	# Don't start more tasks than our limit
	while mesh_updates_in_progress.size() < MAX_CONCURRENT_MESH_TASKS and terrain_world.pending_mesh_updates.size() > 0:
		var chunk_key = terrain_world.pending_mesh_updates.pop_front()

		# Skip if already being processed or chunk doesn't exist
		if mesh_updates_in_progress.has(chunk_key) or not terrain_world.chunks.has(chunk_key):
			continue

		var chunk = terrain_world.chunks[chunk_key]
		if not chunk.is_dirty:
			continue

		# Calculate LOD level for this chunk
		var lod_level: int = get_chunk_lod_level(chunk.chunk_x, chunk.chunk_z)

		# Gather neighbor data for seamless mesh generation
		var neighbors := {}
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nkey := ChunkDataClass.make_key(chunk.chunk_x + dx, chunk.chunk_z + dz)
				if terrain_world.chunks.has(nkey):
					neighbors[nkey] = terrain_world.chunks[nkey]

		# Start threaded task with LOD level
		var task_id = WorkerThreadPool.add_task(
			_generate_mesh_threaded.bind(chunk_key, chunk, neighbors, lod_level)
		)
		mesh_updates_in_progress[chunk_key] = task_id

## Threaded mesh generation (runs in worker thread)
func _generate_mesh_threaded(chunk_key: String, chunk, neighbors: Dictionary, lod_level: int = 0) -> void:
	# Generate mesh data with LOD (this is the expensive part)
	var mesh: ArrayMesh = terrain_world.mesh_generator.generate_mesh(chunk, neighbors, lod_level)
	var collision_shape: ConcavePolygonShape3D = null
	# Only generate collision for high detail chunks (LOD 0 and 1)
	if mesh and lod_level <= 1:
		collision_shape = terrain_world.mesh_generator.generate_collision_shape(mesh)

	# Store result for main thread to apply
	mesh_result_mutex.lock()
	completed_mesh_results.append({
		"chunk_key": chunk_key,
		"mesh": mesh,
		"collision_shape": collision_shape,
		"lod_level": lod_level
	})
	mesh_result_mutex.unlock()

## Apply completed mesh results on main thread (required for scene tree operations)
func apply_completed_meshes() -> void:
	mesh_result_mutex.lock()
	var results_to_apply = completed_mesh_results.duplicate()
	completed_mesh_results.clear()
	mesh_result_mutex.unlock()

	for result in results_to_apply:
		var chunk_key: String = result["chunk_key"]
		var lod_level: int = result.get("lod_level", 0)

		# Remove from in-progress tracking
		mesh_updates_in_progress.erase(chunk_key)

		# Skip if chunk was unloaded while processing
		if not terrain_world.chunks.has(chunk_key):
			continue

		var chunk = terrain_world.chunks[chunk_key]
		var mesh: ArrayMesh = result["mesh"]
		var collision_shape: ConcavePolygonShape3D = result["collision_shape"]

		if mesh == null or mesh.get_surface_count() == 0:
			# Empty chunk or invalid mesh - remove existing mesh if any
			terrain_world._remove_chunk_visuals(chunk_key)
			chunk.is_dirty = false
			terrain_world.chunk_lod_levels.erase(chunk_key)
			continue

		# Store current LOD level
		terrain_world.chunk_lod_levels[chunk_key] = lod_level

		# Create or update MeshInstance3D
		var mesh_instance: MeshInstance3D
		if terrain_world.chunk_meshes.has(chunk_key):
			mesh_instance = terrain_world.chunk_meshes[chunk_key]
		else:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "ChunkMesh_%s" % chunk_key
			terrain_world.add_child(mesh_instance)
			terrain_world.chunk_meshes[chunk_key] = mesh_instance

		mesh_instance.mesh = mesh
		mesh_instance.material_override = terrain_world.terrain_material

		# Create or update collision shape (only for LOD 0 and 1)
		if collision_shape:
			var static_body: StaticBody3D
			if terrain_world.chunk_colliders.has(chunk_key):
				static_body = terrain_world.chunk_colliders[chunk_key]
				# Remove old shape
				for child in static_body.get_children():
					child.queue_free()
			else:
				static_body = StaticBody3D.new()
				static_body.name = "ChunkCollider_%s" % chunk_key
				static_body.collision_layer = 1
				static_body.collision_mask = 0
				terrain_world.add_child(static_body)
				terrain_world.chunk_colliders[chunk_key] = static_body

			var shape_node := CollisionShape3D.new()
			shape_node.shape = collision_shape
			static_body.add_child(shape_node)

		chunk.is_dirty = false

# =============================================================================
# SERVER COLLISION (HEADLESS)
# =============================================================================

var server_collision_queue: Array = []

## Server-side: Generate collision shapes for physics (no visual meshes)
func update_server_collision() -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	const MAX_COLLISION_UPDATES_PER_FRAME := 2

	# Build queue from chunks that need collision
	if server_collision_queue.is_empty():
		for chunk_key in terrain_world.chunks:
			if not terrain_world.chunk_colliders.has(chunk_key):
				server_collision_queue.append(chunk_key)
			elif terrain_world.chunks[chunk_key].is_dirty:
				var old_collider = terrain_world.chunk_colliders[chunk_key]
				old_collider.queue_free()
				terrain_world.chunk_colliders.erase(chunk_key)
				server_collision_queue.append(chunk_key)

	# Process a limited number per frame
	var processed := 0
	while processed < MAX_COLLISION_UPDATES_PER_FRAME and server_collision_queue.size() > 0:
		var chunk_key: String = server_collision_queue.pop_front()

		if not terrain_world.chunks.has(chunk_key):
			continue

		var chunk = terrain_world.chunks[chunk_key]
		_generate_server_collision_for_chunk(chunk)
		processed += 1

## Generate collision shape for a single chunk (server-side, no visual mesh)
func _generate_server_collision_for_chunk(chunk) -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var key: String = chunk.get_key()

	# Skip if already has collision
	if terrain_world.chunk_colliders.has(key):
		chunk.is_dirty = false
		return

	# Gather neighbor chunks
	var neighbors := {}
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nkey := ChunkDataClass.make_key(chunk.chunk_x + dx, chunk.chunk_z + dz)
			if terrain_world.chunks.has(nkey):
				neighbors[nkey] = terrain_world.chunks[nkey]

	# Generate mesh (required for collision shape generation)
	var mesh: ArrayMesh = terrain_world.mesh_generator.generate_mesh(chunk, neighbors, 1)  # LOD 1

	if mesh == null or mesh.get_surface_count() == 0:
		chunk.is_dirty = false
		return

	# Generate collision shape from mesh
	var collision_shape: ConcavePolygonShape3D = terrain_world.mesh_generator.generate_collision_shape(mesh)
	if collision_shape:
		var static_body := StaticBody3D.new()
		static_body.name = "ChunkCollider_%s" % key
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		terrain_world.add_child(static_body)
		terrain_world.chunk_colliders[key] = static_body
		print("[TerrainMeshManager] Generated server collision for chunk %s" % key)

		var shape_node := CollisionShape3D.new()
		shape_node.shape = collision_shape
		static_body.add_child(shape_node)

	chunk.is_dirty = false
