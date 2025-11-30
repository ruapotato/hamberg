extends Node3D
class_name TerrainWorld

## TerrainWorld - Custom voxel terrain system replacing VoxelTools
## Minecraft-style chunked voxels with Valheim-style smooth rendering
## Full control over multiplayer sync and persistence

const ChunkDataClass = preload("res://shared/custom_terrain/chunk_data.gd")
const ChunkMeshGeneratorClass = preload("res://shared/custom_terrain/chunk_mesh_generator.gd")

# Signals
signal chunk_loaded(chunk_x: int, chunk_z: int)
signal chunk_unloaded(chunk_x: int, chunk_z: int)
signal terrain_modified(chunk_x: int, chunk_z: int, operation: String, position: Vector3)

# Terrain generation
var biome_generator  # BiomeGenerator instance
var mesh_generator  # ChunkMeshGenerator instance

# Chunk storage
var chunks: Dictionary = {}  # Key: "x,z" -> ChunkData
var chunk_meshes: Dictionary = {}  # Key: "x,z" -> MeshInstance3D
var chunk_colliders: Dictionary = {}  # Key: "x,z" -> StaticBody3D
var chunk_lod_levels: Dictionary = {}  # Key: "x,z" -> current LOD level

# Configuration
var view_distance: int = 12  # Chunks to load around player (increased with LOD)

# LOD distances (in chunks from player)
const LOD_DISTANCES: Array = [3, 6, 10]  # LOD 0 within 3 chunks, LOD 1 within 6, LOD 2 within 10, LOD 3 beyond
var world_seed: int = 42
var world_name: String = "default"

# State
var is_server: bool = false
var is_initialized: bool = false

# Player tracking for chunk loading
var tracked_players: Dictionary = {}  # peer_id -> Node3D

# Chunk manager for environmental objects
var chunk_manager  # Will be set up after initialization

# Material for terrain rendering
@export var terrain_material: Material

# Dynamic biome texture system (follows player for shader alignment)
var biome_texture: ImageTexture = null
var biome_texture_center: Vector2 = Vector2.ZERO
var biome_texture_last_update_pos: Vector2 = Vector2.ZERO
const BIOME_TEXTURE_SIZE: int = 256  # Resolution of the texture
const BIOME_TEXTURE_WORLD_SIZE: float = 512.0  # World units covered by texture
const BIOME_TEXTURE_UPDATE_THRESHOLD: float = 64.0  # Regenerate when player moves this far

# Threading for mesh generation
var pending_mesh_updates: Array = []  # Chunks waiting to be processed
var mesh_updates_in_progress: Dictionary = {}  # chunk_key -> task_id (being processed in thread)
var completed_mesh_results: Array = []  # Results ready to apply on main thread
var mesh_result_mutex: Mutex = Mutex.new()
const MAX_CONCURRENT_MESH_TASKS: int = 4  # Max chunks being meshed in parallel

# Chunk loading queue to avoid blocking network
var pending_chunk_loads: Array = []  # Array of [cx, cz]
var chunk_load_timer: float = 0.0
const CHUNK_LOAD_INTERVAL: float = 0.016  # Load chunks every frame (~60fps)
const CHUNKS_PER_FRAME: int = 8  # Load up to 8 chunks per frame (much faster now with heightmaps)

func _ready() -> void:
	print("[TerrainWorld] Initializing custom terrain system...")

	# Add to group so other nodes can find us
	add_to_group("terrain_world")

	# Create mesh generator
	mesh_generator = ChunkMeshGeneratorClass.new()

	# Determine server/client mode
	var parent = get_parent()
	while parent:
		if parent.name == "Server":
			is_server = true
			break
		elif parent.name == "Client":
			is_server = false
			break
		parent = parent.get_parent()

	print("[TerrainWorld] Running as %s" % ("SERVER" if is_server else "CLIENT"))

## Initialize world with seed and name
func initialize_world(config_seed: int, config_world_name: String) -> void:
	world_seed = config_seed
	world_name = config_world_name

	print("[TerrainWorld] Initializing world '%s' with seed %d" % [world_name, world_seed])

	# Create biome generator
	_setup_biome_generator()

	# Setup terrain material
	_setup_terrain_material()

	# Setup environmental object spawning (server only)
	if is_server:
		_setup_chunk_manager()

	is_initialized = true
	print("[TerrainWorld] World initialized")

func _setup_biome_generator() -> void:
	print("[TerrainWorld] Setting up biome generator with seed %d..." % world_seed)

	# Load the custom biome generator (adapted from VoxelGeneratorScript version)
	var BiomeGen = preload("res://shared/custom_terrain/terrain_biome_generator.gd")
	biome_generator = BiomeGen.new(world_seed)

	print("[TerrainWorld] Biome generator configured")

func _setup_terrain_material() -> void:
	print("[TerrainWorld] Setting up terrain material...")

	# Load the terrain shader material
	var material_path = "res://assets/terrain_material.tres"
	if ResourceLoader.exists(material_path):
		terrain_material = load(material_path)
		print("[TerrainWorld] Loaded material: %s (type: %s)" % [material_path, terrain_material.get_class()])
		if terrain_material is ShaderMaterial:
			var shader_mat: ShaderMaterial = terrain_material as ShaderMaterial
			shader_mat.set_shader_parameter("world_seed", world_seed)
			shader_mat.set_shader_parameter("biome_texture_size", BIOME_TEXTURE_WORLD_SIZE)
			print("[TerrainWorld] Set world_seed to %d" % world_seed)
		else:
			push_warning("[TerrainWorld] Material is not ShaderMaterial! Type: %s" % terrain_material.get_class())
	else:
		push_warning("[TerrainWorld] Material file not found: %s" % material_path)
		# Create a simple default material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.6, 0.2)  # Green grass color
		mat.roughness = 0.9
		terrain_material = mat
		print("[TerrainWorld] Using default terrain material")

## Generate biome texture centered at a world position
## Stores blend information: R=primary biome, G=secondary biome, B=blend weight
func _generate_biome_texture(center: Vector2) -> void:
	if not biome_generator:
		return

	# Create image to store biome blend info (RGB format)
	var image := Image.create(BIOME_TEXTURE_SIZE, BIOME_TEXTURE_SIZE, false, Image.FORMAT_RGB8)

	# Calculate world units per pixel
	var units_per_pixel := BIOME_TEXTURE_WORLD_SIZE / float(BIOME_TEXTURE_SIZE)

	# Calculate starting corner
	var start_x := center.x - (BIOME_TEXTURE_WORLD_SIZE * 0.5)
	var start_z := center.y - (BIOME_TEXTURE_WORLD_SIZE * 0.5)

	# Sample biome at each pixel
	for py in BIOME_TEXTURE_SIZE:
		for px in BIOME_TEXTURE_SIZE:
			var world_x := start_x + (px * units_per_pixel)
			var world_z := start_z + (py * units_per_pixel)
			var world_pos := Vector2(world_x, world_z)

			# Get blend weights for smooth transitions
			var blend_weights: Array = biome_generator._get_biome_blend_weights(world_pos)

			# Extract primary and secondary biome with blend weight
			var primary_idx: int = 0
			var secondary_idx: int = 0
			var blend_weight: float = 0.0

			if blend_weights.size() >= 1 and blend_weights[0] is Array and blend_weights[0].size() >= 2:
				primary_idx = blend_weights[0][0]
			if blend_weights.size() >= 2 and blend_weights[1] is Array and blend_weights[1].size() >= 2:
				secondary_idx = blend_weights[1][0]
				blend_weight = blend_weights[1][1]  # Weight of secondary biome

			# Store in RGB: R=primary (0-6 -> 0-0.857), G=secondary, B=blend weight
			var r := float(primary_idx) / 7.0
			var g := float(secondary_idx) / 7.0
			var b := blend_weight
			image.set_pixel(px, py, Color(r, g, b, 1.0))

	# Create or update texture
	if biome_texture == null:
		biome_texture = ImageTexture.create_from_image(image)
	else:
		biome_texture.update(image)

	biome_texture_center = center
	biome_texture_last_update_pos = center

	# Update shader parameters
	if terrain_material is ShaderMaterial:
		var shader_mat: ShaderMaterial = terrain_material as ShaderMaterial
		shader_mat.set_shader_parameter("biome_texture", biome_texture)
		shader_mat.set_shader_parameter("biome_texture_center", biome_texture_center)

## Convert biome name to index (must match shader)
func _biome_name_to_index(biome_name: String) -> int:
	match biome_name:
		"valley": return 0
		"forest": return 1
		"swamp": return 2
		"mountain": return 3
		"desert": return 4
		"wizardland": return 5
		"hell": return 6
		_: return 0

## Update biome texture if player has moved far enough
func _update_biome_texture_for_player(player_pos: Vector3) -> void:
	if is_server:
		return  # Only client needs biome texture for rendering

	var player_xz := Vector2(player_pos.x, player_pos.z)
	var distance_moved := player_xz.distance_to(biome_texture_last_update_pos)

	# Regenerate texture if player moved far enough
	if biome_texture == null or distance_moved > BIOME_TEXTURE_UPDATE_THRESHOLD:
		_generate_biome_texture(player_xz)

func _setup_chunk_manager() -> void:
	print("[TerrainWorld] Setting up environmental object spawning...")

	var ChunkManagerScript = load("res://shared/environmental/chunk_manager.gd")
	chunk_manager = ChunkManagerScript.new()
	chunk_manager.name = "ChunkManager"
	chunk_manager.chunk_size = 32.0
	chunk_manager.load_radius = 8
	chunk_manager.update_interval = 2.0
	add_child(chunk_manager)

	# Pass self as the terrain provider
	chunk_manager.initialize(self)

	print("[TerrainWorld] ChunkManager initialized")

func _process(delta: float) -> void:
	if not is_initialized:
		return

	# Update shader time for grass animation (client only)
	if not is_server and terrain_material is ShaderMaterial:
		var shader_mat: ShaderMaterial = terrain_material as ShaderMaterial
		var current_time = shader_mat.get_shader_parameter("time")
		if current_time == null:
			current_time = 0.0
		shader_mat.set_shader_parameter("time", current_time + delta)

	# Process pending chunk loads (rate limited to avoid blocking network)
	chunk_load_timer += delta
	if chunk_load_timer >= CHUNK_LOAD_INTERVAL and pending_chunk_loads.size() > 0:
		chunk_load_timer = 0.0
		for _i in range(min(CHUNKS_PER_FRAME, pending_chunk_loads.size())):
			if pending_chunk_loads.size() == 0:
				break
			var coords = pending_chunk_loads.pop_front()
			_load_chunk_immediate(coords[0], coords[1])

	# Generate meshes on clients, collision only on server
	if not is_server:
		# Client: Start new mesh generation tasks (threaded)
		_start_threaded_mesh_updates()
		# Client: Apply completed mesh results on main thread
		_apply_completed_meshes()
	else:
		# Server (headless): Generate collision shapes for physics
		# Server doesn't need visual meshes, just collision for enemies/NPCs
		_update_server_collision()

	# Update chunks around players and check for LOD changes
	for peer_id in tracked_players:
		var player = tracked_players[peer_id]
		if is_instance_valid(player):
			_update_chunks_around_position(player.global_position)
			_check_lod_updates(player.global_position)
			# Update dynamic biome texture (client only)
			_update_biome_texture_for_player(player.global_position)

## Check if any chunks need LOD updates (when player moves closer)
func _check_lod_updates(player_pos: Vector3) -> void:
	var player_chunk := ChunkDataClass.world_to_chunk_coords(player_pos)

	# Only check chunks that are loaded and not currently being processed
	for chunk_key in chunks:
		if mesh_updates_in_progress.has(chunk_key):
			continue
		if pending_mesh_updates.has(chunk_key):
			continue

		var chunk = chunks[chunk_key]
		var current_lod: int = chunk_lod_levels.get(chunk_key, -1)
		var desired_lod: int = _get_chunk_lod_level(chunk.chunk_x, chunk.chunk_z)

		# Only upgrade LOD (reduce level number) when player gets closer
		# Don't downgrade to avoid constant regeneration at boundaries
		if current_lod > desired_lod or current_lod == -1:
			chunk.is_dirty = true
			pending_mesh_updates.append(chunk_key)

## Get the LOD level for a chunk based on distance from any tracked player
func _get_chunk_lod_level(cx: int, cz: int) -> int:
	var min_dist_sq: float = INF

	for peer_id in tracked_players:
		var player = tracked_players[peer_id]
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

## Start threaded mesh generation for pending chunks
func _start_threaded_mesh_updates() -> void:
	# Don't start more tasks than our limit
	while mesh_updates_in_progress.size() < MAX_CONCURRENT_MESH_TASKS and pending_mesh_updates.size() > 0:
		var chunk_key = pending_mesh_updates.pop_front()

		# Skip if already being processed or chunk doesn't exist
		if mesh_updates_in_progress.has(chunk_key) or not chunks.has(chunk_key):
			continue

		var chunk = chunks[chunk_key]
		if not chunk.is_dirty:
			continue

		# Calculate LOD level for this chunk
		var lod_level: int = _get_chunk_lod_level(chunk.chunk_x, chunk.chunk_z)

		# Gather neighbor data for seamless mesh generation
		var neighbors := {}
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nkey := ChunkDataClass.make_key(chunk.chunk_x + dx, chunk.chunk_z + dz)
				if chunks.has(nkey):
					neighbors[nkey] = chunks[nkey]

		# Start threaded task with LOD level
		var task_id = WorkerThreadPool.add_task(
			_generate_mesh_threaded.bind(chunk_key, chunk, neighbors, lod_level)
		)
		mesh_updates_in_progress[chunk_key] = task_id

## Threaded mesh generation (runs in worker thread)
func _generate_mesh_threaded(chunk_key: String, chunk, neighbors: Dictionary, lod_level: int = 0) -> void:
	# Generate mesh data with LOD (this is the expensive part)
	var mesh: ArrayMesh = mesh_generator.generate_mesh(chunk, neighbors, lod_level)
	var collision_shape: ConcavePolygonShape3D = null
	# Only generate collision for high detail chunks (LOD 0 and 1)
	if mesh and lod_level <= 1:
		collision_shape = mesh_generator.generate_collision_shape(mesh)

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
func _apply_completed_meshes() -> void:
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
		if not chunks.has(chunk_key):
			continue

		var chunk = chunks[chunk_key]
		var mesh: ArrayMesh = result["mesh"]
		var collision_shape: ConcavePolygonShape3D = result["collision_shape"]

		if mesh == null or mesh.get_surface_count() == 0:
			# Empty chunk or invalid mesh - remove existing mesh if any
			_remove_chunk_visuals(chunk_key)
			chunk.is_dirty = false
			chunk_lod_levels.erase(chunk_key)
			continue

		# Store current LOD level
		chunk_lod_levels[chunk_key] = lod_level

		# Create or update MeshInstance3D
		var mesh_instance: MeshInstance3D
		if chunk_meshes.has(chunk_key):
			mesh_instance = chunk_meshes[chunk_key]
		else:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "ChunkMesh_%s" % chunk_key
			add_child(mesh_instance)
			chunk_meshes[chunk_key] = mesh_instance

		mesh_instance.mesh = mesh
		mesh_instance.material_override = terrain_material

		# Create or update collision shape (only for LOD 0 and 1)
		if collision_shape:
			var static_body: StaticBody3D
			if chunk_colliders.has(chunk_key):
				static_body = chunk_colliders[chunk_key]
				# Remove old shape
				for child in static_body.get_children():
					child.queue_free()
			else:
				static_body = StaticBody3D.new()
				static_body.name = "ChunkCollider_%s" % chunk_key
				static_body.collision_layer = 1
				static_body.collision_mask = 0
				add_child(static_body)
				chunk_colliders[chunk_key] = static_body

			var shape_node := CollisionShape3D.new()
			shape_node.shape = collision_shape
			static_body.add_child(shape_node)

		chunk.is_dirty = false

## Register a player for chunk loading
func register_player_for_spawning(peer_id: int, player_node: Node3D) -> void:
	tracked_players[peer_id] = player_node
	print("[TerrainWorld] Registered player %d for chunk loading" % peer_id)

	# Immediately load chunks around player
	if is_instance_valid(player_node):
		_update_chunks_around_position(player_node.global_position)
		# Note: Chunks received before player spawn will be at high LOD initially.
		# The normal _check_lod_updates() in _process() will upgrade them to proper LOD
		# with collision over the next few frames.

## Unregister a player
func unregister_player_from_spawning(peer_id: int) -> void:
	tracked_players.erase(peer_id)
	print("[TerrainWorld] Unregistered player %d" % peer_id)

## Update player position for chunk loading
func update_player_spawn_position(peer_id: int, position: Vector3) -> void:
	if chunk_manager:
		chunk_manager.update_player_position(peer_id, position)

## Update chunks around a world position
func _update_chunks_around_position(world_pos: Vector3) -> void:
	var center_chunk := ChunkDataClass.world_to_chunk_coords(world_pos)

	# Collect chunks to load with their distances
	var chunks_to_queue: Array = []

	for dx in range(-view_distance, view_distance + 1):
		for dz in range(-view_distance, view_distance + 1):
			var cx := center_chunk.x + dx
			var cz := center_chunk.y + dz

			# Skip if too far (circular check)
			var dist_sq := dx * dx + dz * dz
			if dist_sq > view_distance * view_distance:
				continue

			var key := ChunkDataClass.make_key(cx, cz)
			if not chunks.has(key):
				# Check if already queued
				var already_queued := false
				for pending in pending_chunk_loads:
					if pending[0] == cx and pending[1] == cz:
						already_queued = true
						break
				if not already_queued:
					chunks_to_queue.append([cx, cz, dist_sq])

	# Sort by distance (closest first)
	chunks_to_queue.sort_custom(func(a, b): return a[2] < b[2])

	# Load the closest chunks immediately with mesh (under player's feet)
	var immediate_load_count := 0
	const MAX_IMMEDIATE_LOADS := 9  # 3x3 area under player
	for chunk_info in chunks_to_queue:
		if immediate_load_count >= MAX_IMMEDIATE_LOADS:
			break
		if chunk_info[2] <= 2:  # Distance squared <= 2 means adjacent or same chunk
			_load_chunk_immediate(chunk_info[0], chunk_info[1], true)  # Generate mesh immediately
			immediate_load_count += 1

	# Queue the rest (already sorted by distance)
	for chunk_info in chunks_to_queue:
		if chunk_info[2] > 2:  # Skip already loaded immediate chunks
			_load_chunk(chunk_info[0], chunk_info[1])

	# Unload chunks too far away
	var chunks_to_unload: Array = []
	for chunk_key in chunks:
		var chunk = chunks[chunk_key]
		var dist_x: int = chunk.chunk_x - center_chunk.x
		var dist_z: int = chunk.chunk_z - center_chunk.y
		if dist_x * dist_x + dist_z * dist_z > (view_distance + 2) * (view_distance + 2):
			chunks_to_unload.append(chunk_key)

	for key in chunks_to_unload:
		_unload_chunk(key)

## Queue a chunk for loading (non-blocking)
func _load_chunk(cx: int, cz: int) -> void:
	var key := ChunkDataClass.make_key(cx, cz)
	if chunks.has(key):
		return

	# Check if already queued
	var coords := [cx, cz]
	for pending in pending_chunk_loads:
		if pending[0] == cx and pending[1] == cz:
			return

	pending_chunk_loads.append(coords)

## Load a chunk immediately (called from queue processor)
## If generate_mesh_now is true, also generates the mesh synchronously (for player spawn)
func _load_chunk_immediate(cx: int, cz: int, generate_mesh_now: bool = false) -> void:
	var key := ChunkDataClass.make_key(cx, cz)
	if chunks.has(key):
		# If chunk exists but needs immediate mesh, generate it now
		if generate_mesh_now and chunks[key].is_dirty:
			_update_chunk_mesh(chunks[key])
		return

	# Try to load from disk first
	var chunk = _load_chunk_from_disk(cx, cz)

	if chunk == null:
		# Generate new chunk
		chunk = _generate_chunk(cx, cz)

	chunks[key] = chunk

	if generate_mesh_now:
		# Generate mesh immediately (blocking) - for player spawn area
		_update_chunk_mesh(chunk)
	else:
		# Queue mesh generation
		if not pending_mesh_updates.has(key):
			pending_mesh_updates.append(key)

	# Mark neighbor chunks as needing mesh update (for seamless boundaries)
	_queue_neighbor_mesh_updates(cx, cz)

	emit_signal("chunk_loaded", cx, cz)

## Queue mesh updates for neighboring chunks (needed for seamless boundaries)
func _queue_neighbor_mesh_updates(cx: int, cz: int) -> void:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nkey := ChunkDataClass.make_key(cx + dx, cz + dz)
			if chunks.has(nkey) and not pending_mesh_updates.has(nkey):
				chunks[nkey].is_dirty = true
				pending_mesh_updates.append(nkey)

## Generate a new chunk procedurally
func _generate_chunk(cx: int, cz: int):
	var chunk := ChunkDataClass.new(cx, cz)

	# Generate heightmap (much faster - only 256 samples per chunk)
	var heights := PackedFloat32Array()
	heights.resize(ChunkDataClass.CHUNK_SIZE_XZ * ChunkDataClass.CHUNK_SIZE_XZ)

	for lz in ChunkDataClass.CHUNK_SIZE_XZ:
		for lx in ChunkDataClass.CHUNK_SIZE_XZ:
			var world_x := cx * ChunkDataClass.CHUNK_SIZE_XZ + lx
			var world_z := cz * ChunkDataClass.CHUNK_SIZE_XZ + lz
			var world_pos := Vector2(world_x, world_z)

			var terrain_height: float = biome_generator.get_height_at_position(world_pos)
			heights[lx + lz * ChunkDataClass.CHUNK_SIZE_XZ] = terrain_height

	chunk.fill_from_heights(heights)
	return chunk

## Update mesh for a chunk
func _update_chunk_mesh(chunk) -> void:
	if not chunk.is_dirty:
		return

	var key: String = chunk.get_key()

	# Gather neighbor chunks for seamless mesh generation
	var neighbors := {}
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nkey := ChunkDataClass.make_key(chunk.chunk_x + dx, chunk.chunk_z + dz)
			if chunks.has(nkey):
				neighbors[nkey] = chunks[nkey]

	# Generate mesh
	var mesh: ArrayMesh = mesh_generator.generate_mesh(chunk, neighbors)

	if mesh == null:
		# Empty chunk - remove existing mesh if any
		_remove_chunk_visuals(key)
		chunk.is_dirty = false
		return

	# Create or update MeshInstance3D
	var mesh_instance: MeshInstance3D
	if chunk_meshes.has(key):
		mesh_instance = chunk_meshes[key]
	else:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "ChunkMesh_%s" % key
		add_child(mesh_instance)
		chunk_meshes[key] = mesh_instance

	mesh_instance.mesh = mesh
	mesh_instance.material_override = terrain_material

	# Create or update collision shape
	var collision_shape: ConcavePolygonShape3D = mesh_generator.generate_collision_shape(mesh)
	if collision_shape:
		var static_body: StaticBody3D
		if chunk_colliders.has(key):
			static_body = chunk_colliders[key]
			# Remove old shape
			for child in static_body.get_children():
				child.queue_free()
		else:
			static_body = StaticBody3D.new()
			static_body.name = "ChunkCollider_%s" % key
			# Set collision layer to World (layer 1)
			static_body.collision_layer = 1
			static_body.collision_mask = 0
			add_child(static_body)
			chunk_colliders[key] = static_body

		var shape_node := CollisionShape3D.new()
		shape_node.shape = collision_shape
		static_body.add_child(shape_node)

	chunk.is_dirty = false

## Server-side: Generate collision shapes for physics (no visual meshes)
## Called every frame to process dirty chunks
var server_collision_queue: Array = []

func _update_server_collision() -> void:
	# Process pending collision updates (rate limited)
	const MAX_COLLISION_UPDATES_PER_FRAME := 2

	# Build queue from chunks that need collision (no collider yet OR dirty)
	if server_collision_queue.is_empty():
		for chunk_key in chunks:
			# Queue chunks that don't have collision yet, or need regeneration
			if not chunk_colliders.has(chunk_key):
				server_collision_queue.append(chunk_key)
			elif chunks[chunk_key].is_dirty:
				# Chunk was modified - remove old collider and regenerate
				var old_collider = chunk_colliders[chunk_key]
				old_collider.queue_free()
				chunk_colliders.erase(chunk_key)
				server_collision_queue.append(chunk_key)

	# Process a limited number per frame
	var processed := 0
	while processed < MAX_COLLISION_UPDATES_PER_FRAME and server_collision_queue.size() > 0:
		var chunk_key: String = server_collision_queue.pop_front()

		if not chunks.has(chunk_key):
			continue

		var chunk = chunks[chunk_key]
		_generate_server_collision_for_chunk(chunk)
		processed += 1

## Generate collision shape for a single chunk (server-side, no visual mesh)
func _generate_server_collision_for_chunk(chunk) -> void:
	var key: String = chunk.get_key()

	# Skip if already has collision
	if chunk_colliders.has(key):
		chunk.is_dirty = false
		return

	# Gather neighbor chunks for seamless collision generation
	var neighbors := {}
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nkey := ChunkDataClass.make_key(chunk.chunk_x + dx, chunk.chunk_z + dz)
			if chunks.has(nkey):
				neighbors[nkey] = chunks[nkey]

	# Generate mesh (required for collision shape generation)
	var mesh: ArrayMesh = mesh_generator.generate_mesh(chunk, neighbors, 1)  # LOD 1 for faster generation

	if mesh == null or mesh.get_surface_count() == 0:
		chunk.is_dirty = false
		return

	# Generate collision shape from mesh
	var collision_shape: ConcavePolygonShape3D = mesh_generator.generate_collision_shape(mesh)
	if collision_shape:
		var static_body := StaticBody3D.new()
		static_body.name = "ChunkCollider_%s" % key
		static_body.collision_layer = 1  # World layer
		static_body.collision_mask = 0
		add_child(static_body)
		chunk_colliders[key] = static_body
		print("[TerrainWorld] Generated server collision for chunk %s" % key)

		var shape_node := CollisionShape3D.new()
		shape_node.shape = collision_shape
		static_body.add_child(shape_node)

	chunk.is_dirty = false

## Remove visual elements for a chunk
func _remove_chunk_visuals(key: String) -> void:
	if chunk_meshes.has(key):
		chunk_meshes[key].queue_free()
		chunk_meshes.erase(key)

	if chunk_colliders.has(key):
		chunk_colliders[key].queue_free()
		chunk_colliders.erase(key)

## Unload a chunk
func _unload_chunk(key: String) -> void:
	if not chunks.has(key):
		return

	var chunk = chunks[key]

	# Save if modified
	if chunk.is_modified:
		_save_chunk_to_disk(chunk)

	# Remove visuals
	_remove_chunk_visuals(key)

	# Remove from storage
	chunks.erase(key)
	pending_mesh_updates.erase(key)

	emit_signal("chunk_unloaded", chunk.chunk_x, chunk.chunk_z)

## Save a chunk to disk
func _save_chunk_to_disk(chunk) -> void:
	var save_dir := "user://worlds/%s/terrain/" % world_name
	DirAccess.make_dir_recursive_absolute(save_dir)

	var file_path := save_dir + "%d_%d.chunk" % [chunk.chunk_x, chunk.chunk_z]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(chunk.serialize()))
		file.close()

## Load a chunk from disk
func _load_chunk_from_disk(cx: int, cz: int):
	var file_path := "user://worlds/%s/terrain/%d_%d.chunk" % [world_name, cx, cz]

	if not FileAccess.file_exists(file_path):
		return null

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("[TerrainWorld] ERROR: Failed to open chunk file at %s" % file_path)
		return null

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		print("[TerrainWorld] ERROR: Failed to parse JSON for chunk (%d, %d): %s" % [cx, cz, json.get_error_message()])
		return null

	var chunk = ChunkDataClass.deserialize(json.data)
	return chunk

# =============================================================================
# TERRAIN MODIFICATION API
# =============================================================================

## Dig a square hole at the target position
func dig_square(world_position: Vector3, tool_name: String = "stone_pickaxe") -> int:
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not chunks.has(key):
		push_warning("[TerrainWorld] Cannot dig - chunk not loaded at %s" % world_position)
		return 0

	var chunk = chunks[key]

	# Calculate operation area (3x3x3 block centered on target)
	var center_x := int(floor(world_position.x)) - 1
	var center_y := int(floor(world_position.y)) - 1
	var center_z := int(floor(world_position.z)) - 1

	var any_material_removed := false

	# Remove voxels in a 3x3x3 area for alignment with preview
	for dx in range(0, 3):
		for dy in range(0, 3):
			for dz in range(0, 3):
				var wx := center_x + dx
				var wy := center_y + dy
				var wz := center_z + dz

				# Get current density
				var current := _get_voxel_at(wx, wy, wz)
				if current > 0.1:
					any_material_removed = true

				# Set to air
				_set_voxel_at(wx, wy, wz, 0.0)

	# Mark chunk and neighbors as dirty
	_mark_area_dirty(world_position)

	emit_signal("terrain_modified", chunk_coords.x, chunk_coords.y, "dig_square", world_position)

	# 1 dig = 1 earth (balanced gameplay)
	return 1 if any_material_removed else 0

## Place earth in a square pattern
func place_square(world_position: Vector3, earth_amount: int) -> int:
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not chunks.has(key):
		push_warning("[TerrainWorld] Cannot place - chunk not loaded at %s" % world_position)
		return 0

	var chunk = chunks[key]

	var center_x := int(floor(world_position.x)) - 1
	var center_y := int(floor(world_position.y)) - 1
	var center_z := int(floor(world_position.z)) - 1

	var any_material_placed := false

	# Add solid voxels in a 3x3x3 cube area to match dig_square
	for dx in range(0, 3):
		for dy in range(0, 3):
			for dz in range(0, 3):
				var wx := center_x + dx
				var wy := center_y + dy
				var wz := center_z + dz

				# Calculate density based on distance from center (solid in center, gradient at edges)
				var dist := Vector3(dx - 1.0, dy - 1.0, dz - 1.0).length()
				var target_density := 1.0 if dist < 1.5 else 0.7  # Solid core, slightly softer edges

				var current: float = _get_voxel_at(wx, wy, wz)

				# Only place if we're adding material (not removing)
				if target_density > current:
					any_material_placed = true
					_set_voxel_at(wx, wy, wz, target_density)

	_mark_area_dirty(world_position)

	emit_signal("terrain_modified", chunk_coords.x, chunk_coords.y, "place_square", world_position)

	# 1 place = 1 earth cost (balanced gameplay)
	return 1 if any_material_placed else 0

## Flatten terrain to a target height
func flatten_square(world_position: Vector3, target_height: float) -> int:
	var center_x := int(floor(world_position.x))
	var center_z := int(floor(world_position.z))
	var target_y := int(floor(target_height))

	# Flatten a 4x4 area
	for dx in range(-2, 2):
		for dz in range(-2, 2):
			var wx := center_x + dx
			var wz := center_z + dz

			# Remove everything above target height
			for wy in range(target_y + 1, target_y + 10):
				_set_voxel_at(wx, wy, wz, 0.0)

			# Fill everything below target height
			for wy in range(target_y - 5, target_y + 1):
				_set_voxel_at(wx, wy, wz, 1.0)

	_mark_area_dirty(world_position)

	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)
	emit_signal("terrain_modified", chunk_coords.x, chunk_coords.y, "flatten_square", world_position)

	return 0

## Get voxel density at world position
func _get_voxel_at(world_x: int, world_y: int, world_z: int) -> float:
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(Vector3(world_x, 0, world_z))
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not chunks.has(key):
		return 0.0

	return chunks[key].get_voxel_world(world_x, world_y, world_z)

## Set voxel density at world position
func _set_voxel_at(world_x: int, world_y: int, world_z: int, density: float) -> void:
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(Vector3(world_x, 0, world_z))
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)

	if not chunks.has(key):
		return

	chunks[key].set_voxel_world(world_x, world_y, world_z, density)

## Mark area around position as needing mesh update
func _mark_area_dirty(world_position: Vector3) -> void:
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_position)

	# Mark the chunk and its neighbors as dirty
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := ChunkDataClass.make_key(chunk_coords.x + dx, chunk_coords.y + dz)
			if chunks.has(key):
				chunks[key].is_dirty = true
				if not pending_mesh_updates.has(key):
					pending_mesh_updates.append(key)

# =============================================================================
# PUBLIC API (compatibility with old VoxelWorld)
# =============================================================================

## Get terrain height at XZ position
func get_terrain_height_at(xz_pos: Vector2) -> float:
	if biome_generator:
		return biome_generator.get_height_at_position(xz_pos)
	return 0.0

## Get biome at XZ position
func get_biome_at(xz_pos: Vector2) -> String:
	if biome_generator:
		return biome_generator.get_biome_at_position(xz_pos)
	return "valley"

## Find surface position (for spawning)
func find_surface_position(xz_pos: Vector2, search_start_y: float = 100.0, search_range: float = 200.0) -> Vector3:
	# Use raycast for precision
	var start_pos := Vector3(xz_pos.x, search_start_y, xz_pos.y)
	var end_pos := Vector3(xz_pos.x, search_start_y - search_range, xz_pos.y)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.collision_mask = 1

	var result := space_state.intersect_ray(query)
	if result:
		return result.position

	# Fallback to height estimation
	return Vector3(xz_pos.x, get_terrain_height_at(xz_pos), xz_pos.y)

## Check if a position has terrain collision loaded (for safe spawning)
## Both server and client now check actual collision shapes
func has_collision_at_position(world_pos: Vector3) -> bool:
	var chunk_coords := ChunkDataClass.world_to_chunk_coords(world_pos)
	var key := ChunkDataClass.make_key(chunk_coords.x, chunk_coords.y)
	return chunk_colliders.has(key)

## Save all modified chunks
func save_environmental_chunks() -> void:
	if chunk_manager:
		chunk_manager.save_all_modified_chunks()

	# Save all modified terrain chunks
	var saved_count := 0
	for key in chunks:
		var chunk = chunks[key]
		if chunk.is_modified:
			_save_chunk_to_disk(chunk)
			saved_count += 1

	print("[TerrainWorld] Saved %d modified terrain chunks" % saved_count)

## Get all modified chunks (for sending to new clients)
## Any chunk saved to disk is considered modified (only modified chunks are saved)
func get_all_modified_chunks() -> Array:
	var modified_chunks := []
	var added_keys := {}  # Track which chunks we've added

	# Check loaded chunks first
	for key in chunks:
		var chunk = chunks[key]
		if chunk.is_modified:
			modified_chunks.append({
				"chunk_x": chunk.chunk_x,
				"chunk_z": chunk.chunk_z,
				"data": chunk.serialize()
			})
			added_keys[key] = true

	# Also load any saved chunks from disk that aren't currently loaded
	# Any chunk file on disk was saved because it was modified
	if is_server:
		var save_dir := "user://worlds/%s/terrain/" % world_name
		if DirAccess.dir_exists_absolute(save_dir):
			var dir := DirAccess.open(save_dir)
			if dir:
				dir.list_dir_begin()
				var file_name := dir.get_next()
				while file_name != "":
					if file_name.ends_with(".chunk"):
						# Parse chunk coordinates from filename (format: x_z.chunk)
						var parts := file_name.trim_suffix(".chunk").split("_")
						if parts.size() >= 2:
							# Handle negative coordinates (e.g., "-1_-2.chunk" splits to ["", "1", "", "2"])
							# Use rsplit to handle this better
							var cx: int = 0
							var cz: int = 0
							var base_name := file_name.trim_suffix(".chunk")
							var last_underscore := base_name.rfind("_")
							if last_underscore > 0:
								cx = base_name.substr(0, last_underscore).to_int()
								cz = base_name.substr(last_underscore + 1).to_int()
							else:
								# Fallback to simple split
								cx = parts[0].to_int()
								cz = parts[1].to_int()

							var key := ChunkDataClass.make_key(cx, cz)

							# Only add if not already added from loaded chunks
							if not added_keys.has(key):
								var chunk_data_from_disk = _load_chunk_from_disk(cx, cz)
								if chunk_data_from_disk:
									# Force is_modified since it was saved to disk
									chunk_data_from_disk.is_modified = true
									modified_chunks.append({
										"chunk_x": cx,
										"chunk_z": cz,
										"data": chunk_data_from_disk.serialize()
									})
									added_keys[key] = true
					file_name = dir.get_next()
				dir.list_dir_end()

	print("[TerrainWorld] Found %d modified chunks to send" % modified_chunks.size())
	return modified_chunks

## Apply a received chunk from server
func apply_received_chunk(chunk_x: int, chunk_z: int, chunk_data: Dictionary) -> void:
	var key := ChunkDataClass.make_key(chunk_x, chunk_z)
	var chunk = ChunkDataClass.deserialize(chunk_data)

	chunks[key] = chunk
	chunk.is_dirty = true

	# Queue mesh generation
	if not pending_mesh_updates.has(key):
		pending_mesh_updates.append(key)

	# Mark neighbors as needing mesh update
	_queue_neighbor_mesh_updates(chunk_x, chunk_z)

## Apply a terrain modification from network
func apply_network_modification(operation: String, position: Vector3, data: Dictionary) -> void:
	match operation:
		"dig_square":
			var tool_name = data.get("tool", "stone_pickaxe")
			dig_square(position, tool_name)
		"place_square":
			var earth_amount = data.get("earth_amount", 1)
			place_square(position, earth_amount)
		"flatten_square":
			var target_height = data.get("target_height", position.y)
			flatten_square(position, target_height)

