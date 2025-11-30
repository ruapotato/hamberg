class_name TerrainChunkLoader
extends RefCounted

## TerrainChunkLoader - Handles chunk loading, unloading, and persistence

var terrain_world: Node3D

# Chunk loading queue to avoid blocking network
var pending_chunk_loads: Array = []  # Array of [cx, cz]
var chunk_load_timer: float = 0.0
const CHUNK_LOAD_INTERVAL: float = 0.016  # Load chunks every frame (~60fps)
const CHUNKS_PER_FRAME: int = 8  # Load up to 8 chunks per frame

func _init(tw: Node3D) -> void:
	terrain_world = tw

# =============================================================================
# CHUNK LOADING
# =============================================================================

## Process pending chunk loads (rate limited)
func process_pending_loads(delta: float) -> void:
	chunk_load_timer += delta
	if chunk_load_timer >= CHUNK_LOAD_INTERVAL and pending_chunk_loads.size() > 0:
		chunk_load_timer = 0.0
		for _i in range(min(CHUNKS_PER_FRAME, pending_chunk_loads.size())):
			if pending_chunk_loads.size() == 0:
				break
			var coords = pending_chunk_loads.pop_front()
			load_chunk_immediate(coords[0], coords[1])

## Queue a chunk for loading (non-blocking)
func queue_load(cx: int, cz: int) -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var key := ChunkDataClass.make_key(cx, cz)
	if terrain_world.chunks.has(key):
		return

	# Check if already queued
	for pending in pending_chunk_loads:
		if pending[0] == cx and pending[1] == cz:
			return

	pending_chunk_loads.append([cx, cz])

## Load a chunk immediately
## If generate_mesh_now is true, also generates the mesh synchronously (for player spawn)
func load_chunk_immediate(cx: int, cz: int, generate_mesh_now: bool = false) -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var key := ChunkDataClass.make_key(cx, cz)
	if terrain_world.chunks.has(key):
		# If chunk exists but needs immediate mesh, generate it now
		if generate_mesh_now and terrain_world.chunks[key].is_dirty:
			terrain_world._update_chunk_mesh(terrain_world.chunks[key])
		return

	# Try to load from disk first
	var chunk = load_from_disk(cx, cz)

	if chunk == null:
		# Generate new chunk
		chunk = generate_chunk(cx, cz)

	terrain_world.chunks[key] = chunk

	if generate_mesh_now:
		# Generate mesh immediately (blocking) - for player spawn area
		terrain_world._update_chunk_mesh(chunk)
	else:
		# Queue mesh generation
		if not terrain_world.pending_mesh_updates.has(key):
			terrain_world.pending_mesh_updates.append(key)

	# Mark neighbor chunks as needing mesh update (for seamless boundaries)
	queue_neighbor_mesh_updates(cx, cz)

	terrain_world.emit_signal("chunk_loaded", cx, cz)

## Queue mesh updates for neighboring chunks (needed for seamless boundaries)
func queue_neighbor_mesh_updates(cx: int, cz: int) -> void:
	var ChunkDataClass = terrain_world.ChunkDataClass
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nkey := ChunkDataClass.make_key(cx + dx, cz + dz)
			if terrain_world.chunks.has(nkey) and not terrain_world.pending_mesh_updates.has(nkey):
				terrain_world.chunks[nkey].is_dirty = true
				terrain_world.pending_mesh_updates.append(nkey)

## Generate a new chunk procedurally
func generate_chunk(cx: int, cz: int):
	var ChunkDataClass = terrain_world.ChunkDataClass
	var chunk := ChunkDataClass.new(cx, cz)

	# Generate heightmap (much faster - only 256 samples per chunk)
	var heights := PackedFloat32Array()
	heights.resize(ChunkDataClass.CHUNK_SIZE_XZ * ChunkDataClass.CHUNK_SIZE_XZ)

	for lz in ChunkDataClass.CHUNK_SIZE_XZ:
		for lx in ChunkDataClass.CHUNK_SIZE_XZ:
			var world_x := cx * ChunkDataClass.CHUNK_SIZE_XZ + lx
			var world_z := cz * ChunkDataClass.CHUNK_SIZE_XZ + lz
			var world_pos := Vector2(world_x, world_z)

			var terrain_height: float = terrain_world.biome_generator.get_height_at_position(world_pos)
			heights[lx + lz * ChunkDataClass.CHUNK_SIZE_XZ] = terrain_height

	chunk.fill_from_heights(heights)
	return chunk

# =============================================================================
# CHUNK UNLOADING
# =============================================================================

## Unload a chunk
func unload_chunk(key: String) -> void:
	if not terrain_world.chunks.has(key):
		return

	var chunk = terrain_world.chunks[key]

	# Save if modified
	if chunk.is_modified:
		save_to_disk(chunk)

	# Remove visuals
	terrain_world._remove_chunk_visuals(key)

	# Remove from storage
	terrain_world.chunks.erase(key)
	terrain_world.pending_mesh_updates.erase(key)

	terrain_world.emit_signal("chunk_unloaded", chunk.chunk_x, chunk.chunk_z)

# =============================================================================
# PERSISTENCE
# =============================================================================

## Save a chunk to disk
func save_to_disk(chunk) -> void:
	var save_dir := "user://worlds/%s/terrain/" % terrain_world.world_name
	DirAccess.make_dir_recursive_absolute(save_dir)

	var file_path := save_dir + "%d_%d.chunk" % [chunk.chunk_x, chunk.chunk_z]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(chunk.serialize()))
		file.close()

## Load a chunk from disk
func load_from_disk(cx: int, cz: int):
	var file_path := "user://worlds/%s/terrain/%d_%d.chunk" % [terrain_world.world_name, cx, cz]

	if not FileAccess.file_exists(file_path):
		return null

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("[TerrainChunkLoader] ERROR: Failed to open chunk file at %s" % file_path)
		return null

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		print("[TerrainChunkLoader] ERROR: Failed to parse JSON for chunk (%d, %d): %s" % [cx, cz, json.get_error_message()])
		return null

	var ChunkDataClass = terrain_world.ChunkDataClass
	var chunk = ChunkDataClass.deserialize(json.data)
	return chunk

## Save all modified chunks
func save_all_modified() -> void:
	var saved_count := 0
	for key in terrain_world.chunks:
		var chunk = terrain_world.chunks[key]
		if chunk.is_modified:
			save_to_disk(chunk)
			saved_count += 1

	print("[TerrainChunkLoader] Saved %d modified terrain chunks" % saved_count)

## Get all modified chunks (for sending to new clients)
func get_all_modified() -> Array:
	var ChunkDataClass = terrain_world.ChunkDataClass
	var modified_chunks := []
	var added_keys := {}  # Track which chunks we've added

	# Check loaded chunks first
	for key in terrain_world.chunks:
		var chunk = terrain_world.chunks[key]
		if chunk.is_modified:
			modified_chunks.append({
				"chunk_x": chunk.chunk_x,
				"chunk_z": chunk.chunk_z,
				"data": chunk.serialize()
			})
			added_keys[key] = true

	# Also load any saved chunks from disk that aren't currently loaded
	if terrain_world.is_server:
		var save_dir := "user://worlds/%s/terrain/" % terrain_world.world_name
		if DirAccess.dir_exists_absolute(save_dir):
			var dir := DirAccess.open(save_dir)
			if dir:
				dir.list_dir_begin()
				var file_name := dir.get_next()
				while file_name != "":
					if file_name.ends_with(".chunk"):
						var base_name := file_name.trim_suffix(".chunk")
						var last_underscore := base_name.rfind("_")
						if last_underscore > 0:
							var cx := base_name.substr(0, last_underscore).to_int()
							var cz := base_name.substr(last_underscore + 1).to_int()
							var key := ChunkDataClass.make_key(cx, cz)

							if not added_keys.has(key):
								var chunk_data_from_disk = load_from_disk(cx, cz)
								if chunk_data_from_disk:
									chunk_data_from_disk.is_modified = true
									modified_chunks.append({
										"chunk_x": cx,
										"chunk_z": cz,
										"data": chunk_data_from_disk.serialize()
									})
									added_keys[key] = true
					file_name = dir.get_next()
				dir.list_dir_end()

	print("[TerrainChunkLoader] Found %d modified chunks to send" % modified_chunks.size())
	return modified_chunks
