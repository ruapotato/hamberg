extends Node

## ChunkDatabase - Manages persistent storage of chunk data
## Handles in-memory cache and disk serialization

# Preload the ChunkData script
const ChunkDataScript = preload("res://shared/environmental/chunk_data.gd")

# In-memory storage
var chunks: Dictionary = {}  # Vector2i -> ChunkData reference

# Save path (configured per world)
var save_dir: String = "user://worlds/default/chunks/"
var world_name: String = "default"

func _ready() -> void:
	# Save directory will be set when world is initialized
	pass

## Initialize database for a specific world
func initialize_for_world(new_world_name: String) -> void:
	world_name = new_world_name
	save_dir = "user://worlds/" + world_name + "/chunks/"

	# Ensure save directory exists
	var dir := DirAccess.open("user://")
	if not dir.dir_exists("worlds"):
		dir.make_dir("worlds")

	dir = DirAccess.open("user://worlds")
	if not dir.dir_exists(world_name):
		dir.make_dir(world_name)

	dir = DirAccess.open("user://worlds/" + world_name)
	if not dir.dir_exists("chunks"):
		dir.make_dir("chunks")

	print("[ChunkDatabase] Initialized for world '%s' at %s" % [world_name, save_dir])

## Get chunk data, creating new if doesn't exist
func get_chunk(chunk_pos: Vector2i):
	if not chunks.has(chunk_pos):
		# Try to load from disk
		var loaded_data = _load_chunk_from_disk(chunk_pos)
		if loaded_data:
			chunks[chunk_pos] = loaded_data
		else:
			# Create new chunk data
			chunks[chunk_pos] = ChunkDataScript.new(chunk_pos)

	return chunks[chunk_pos]

## Check if chunk has been generated
func is_chunk_generated(chunk_pos: Vector2i) -> bool:
	# Check if chunk file exists on disk
	var save_path = _get_chunk_file_path(chunk_pos)
	return FileAccess.file_exists(save_path)

## Mark chunk as generated
func mark_chunk_generated(chunk_pos: Vector2i) -> void:
	var chunk_data = get_chunk(chunk_pos)
	chunk_data.is_generated = true

## Save a chunk to disk
func save_chunk(chunk_pos: Vector2i) -> void:
	if not chunks.has(chunk_pos):
		return

	var chunk_data = chunks[chunk_pos]
	var save_path = _get_chunk_file_path(chunk_pos)

	# Serialize to JSON
	var data_dict = chunk_data.to_dict()
	var json_string = JSON.stringify(data_dict, "\t")

	# Write to file
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	else:
		push_error("[ChunkDatabase] Failed to save chunk %s: %s" % [chunk_pos, FileAccess.get_open_error()])

## Load a chunk from disk
func _load_chunk_from_disk(chunk_pos: Vector2i):
	var save_path = _get_chunk_file_path(chunk_pos)

	if not FileAccess.file_exists(save_path):
		return null

	# Read file
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return null

	var json_string = file.get_as_text()
	file.close()

	# Parse JSON
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("[ChunkDatabase] Failed to parse chunk data: %s" % json.get_error_message())
		return null

	var data_dict = json.data
	return ChunkDataScript.from_dict(data_dict)

## Unload chunk from memory (save first)
func unload_chunk(chunk_pos: Vector2i) -> void:
	if not chunks.has(chunk_pos):
		return

	save_chunk(chunk_pos)
	chunks.erase(chunk_pos)

## Save all chunks
func save_all() -> void:
	print("[ChunkDatabase] Saving %d chunks..." % chunks.size())
	for chunk_pos in chunks.keys():
		save_chunk(chunk_pos)
	print("[ChunkDatabase] Save complete!")

## Get file path for a chunk
func _get_chunk_file_path(chunk_pos: Vector2i) -> String:
	return save_dir + "chunk_%d_%d.json" % [chunk_pos.x, chunk_pos.y]

## Get stats for debugging
func get_stats() -> Dictionary:
	var generated_count := 0
	var total_objects := 0

	for chunk_data in chunks.values():
		if chunk_data.is_generated:
			generated_count += 1
		total_objects += chunk_data.objects.size()

	return {
		"chunks_in_memory": chunks.size(),
		"generated_chunks": generated_count,
		"total_objects": total_objects
	}
