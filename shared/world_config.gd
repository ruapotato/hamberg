extends Resource
class_name WorldConfig

## WorldConfig - Stores metadata and configuration for a world
## Each world has a unique name and seed for procedural generation

@export var world_name: String = ""
@export var seed: int = 0
@export var created_at: int = 0  # Unix timestamp
@export var last_played: int = 0  # Unix timestamp

## Create a new world config
static func create_new(name: String, world_seed: int = -1):
	var config = load("res://shared/world_config.gd").new()
	config.world_name = name

	# Generate random seed if not provided
	if world_seed == -1:
		randomize()
		config.seed = randi()
	else:
		config.seed = world_seed

	var current_time := Time.get_unix_time_from_system()
	config.created_at = current_time
	config.last_played = current_time

	return config

## Load world config from file
static func load_from_file(world_name: String):
	var path := _get_world_config_path(world_name)

	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[WorldConfig] Failed to open world config: %s" % path)
		return null

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("[WorldConfig] Failed to parse world config: %s" % json.get_error_message())
		return null

	var data: Dictionary = json.data
	return from_dict(data)

## Save world config to file
func save_to_file() -> bool:
	var path := _get_world_config_path(world_name)

	# Ensure worlds directory exists
	_ensure_worlds_directory()

	# Ensure world directory exists
	var world_dir := "user://worlds/" + world_name
	var dir := DirAccess.open("user://worlds")
	if not dir.dir_exists(world_name):
		dir.make_dir(world_name)

	# Update last played time
	last_played = Time.get_unix_time_from_system()

	# Serialize to JSON
	var data := to_dict()
	var json_string := JSON.stringify(data, "\t")

	# Write to file
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[WorldConfig] Failed to save world config: %s" % FileAccess.get_open_error())
		return false

	file.store_string(json_string)
	file.close()

	print("[WorldConfig] Saved world config: %s (seed: %d)" % [world_name, seed])
	return true

## Convert to dictionary for serialization
func to_dict() -> Dictionary:
	return {
		"world_name": world_name,
		"seed": seed,
		"created_at": created_at,
		"last_played": last_played
	}

## Create from dictionary (deserialization)
static func from_dict(data: Dictionary):
	var config = load("res://shared/world_config.gd").new()
	config.world_name = data.get("world_name", "")
	config.seed = data.get("seed", 0)
	config.created_at = data.get("created_at", 0)
	config.last_played = data.get("last_played", 0)
	return config

## Get the file path for this world's config
static func _get_world_config_path(name: String) -> String:
	return "user://worlds/" + name + "/world.json"

## Ensure worlds directory exists
static func _ensure_worlds_directory() -> void:
	var dir := DirAccess.open("user://")
	if not dir.dir_exists("worlds"):
		dir.make_dir("worlds")

## List all available worlds
static func list_worlds() -> Array[String]:
	_ensure_worlds_directory()

	var worlds: Array[String] = []
	var dir := DirAccess.open("user://worlds")

	if not dir:
		return worlds

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			# Check if world.json exists
			if FileAccess.file_exists("user://worlds/" + file_name + "/world.json"):
				worlds.append(file_name)
		file_name = dir.get_next()

	dir.list_dir_end()
	return worlds

## Delete a world
static func delete_world(world_name: String) -> bool:
	var world_path := "user://worlds/" + world_name

	if not DirAccess.dir_exists_absolute(world_path):
		return false

	# Recursively delete world directory
	var dir := DirAccess.open(world_path)
	if not dir:
		return false

	# Delete all files in chunks directory
	if dir.dir_exists("chunks"):
		var chunks_dir := DirAccess.open(world_path + "/chunks")
		if chunks_dir:
			chunks_dir.list_dir_begin()
			var file_name := chunks_dir.get_next()
			while file_name != "":
				if not chunks_dir.current_is_dir():
					chunks_dir.remove(file_name)
				file_name = chunks_dir.get_next()
			chunks_dir.list_dir_end()

		dir.remove("chunks")

	# Delete world.json
	if FileAccess.file_exists(world_path + "/world.json"):
		dir.remove("world.json")

	# Delete world directory
	var parent_dir := DirAccess.open("user://worlds")
	parent_dir.remove(world_name)

	print("[WorldConfig] Deleted world: %s" % world_name)
	return true
