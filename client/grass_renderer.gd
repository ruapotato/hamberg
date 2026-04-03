extends Node3D

## Client-side grass renderer using MultiMesh for performance
## Generates grass per-chunk and manages lifecycle with chunk load/unload events

var grass_chunks: Dictionary = {}  # Vector2i -> MultimeshChunk
var pending_chunks: Array[Vector2i] = []  # Queue for async generation
var terrain_world: Node3D
var spawner: Node
var is_initialized: bool = false

var MultimeshChunkScript = preload("res://shared/environmental/multimesh_chunk.gd")
var EnvironmentalSpawnerScript = preload("res://shared/environmental/environmental_spawner.gd")

const CHUNKS_PER_FRAME := 2  # Process up to 2 chunks per frame to avoid hitching

func initialize(terrain_ref: Node3D, world_seed: int, chunk_size: float = 32.0) -> void:
	terrain_world = terrain_ref

	# Create our own spawner for grass transform generation
	spawner = EnvironmentalSpawnerScript.new()
	spawner.name = "GrassSpawner"
	add_child(spawner)
	spawner.set_world_seed(world_seed)
	spawner.set_chunk_size(chunk_size)

	is_initialized = true

func _process(_delta: float) -> void:
	if not is_initialized or pending_chunks.is_empty():
		return

	# Process queued chunks (spread across frames)
	var processed := 0
	while not pending_chunks.is_empty() and processed < CHUNKS_PER_FRAME:
		var chunk_pos := pending_chunks.pop_front()
		if not grass_chunks.has(chunk_pos):
			_generate_grass_for_chunk(chunk_pos)
		processed += 1

func on_chunk_loaded(chunk_pos: Vector2i) -> void:
	if not is_initialized:
		return
	if grass_chunks.has(chunk_pos):
		return
	if chunk_pos not in pending_chunks:
		pending_chunks.append(chunk_pos)

func on_chunk_unloaded(chunk_pos: Vector2i) -> void:
	# Remove from pending queue if not yet generated
	var idx := pending_chunks.find(chunk_pos)
	if idx >= 0:
		pending_chunks.remove_at(idx)

	# Clean up existing grass chunk
	if grass_chunks.has(chunk_pos):
		grass_chunks[chunk_pos].cleanup()
		grass_chunks[chunk_pos].queue_free()
		grass_chunks.erase(chunk_pos)

func _generate_grass_for_chunk(chunk_pos: Vector2i) -> void:
	if not terrain_world or not spawner:
		return

	var transforms := spawner.generate_dense_grass_transforms(chunk_pos, terrain_world)
	if transforms.is_empty():
		return

	var mm_chunk := MultimeshChunkScript.new()
	mm_chunk.set_chunk_position(chunk_pos)
	add_child(mm_chunk)
	mm_chunk.add_decoration_instances("grass", transforms)
	grass_chunks[chunk_pos] = mm_chunk

func cleanup() -> void:
	for chunk_pos in grass_chunks.keys():
		grass_chunks[chunk_pos].cleanup()
		grass_chunks[chunk_pos].queue_free()
	grass_chunks.clear()
	pending_chunks.clear()
