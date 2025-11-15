extends Node
class_name WorldStateManager

# Manages saving and loading world state (buildables, global events, etc.)
# Stored as: user://worlds/{world_name}/world_state.json

const WORLD_STATE_FILE = "user://worlds/%s/world_state.json"

var world_name: String = ""

func _init(p_world_name: String = ""):
	world_name = p_world_name

func initialize(p_world_name: String) -> void:
	world_name = p_world_name

func save_world_state(buildables: Dictionary, additional_data: Dictionary = {}) -> bool:
	var file_path = WORLD_STATE_FILE % world_name

	var state_data = {
		"buildables": buildables,
		"time_of_day": additional_data.get("time_of_day", 0.5),
		"global_events": additional_data.get("global_events", []),
		"last_saved": Time.get_unix_time_from_system()
	}

	# Serialize to JSON
	var json_string = JSON.stringify(state_data, "\t")

	# Write to file
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("[WorldStateManager] Failed to open file for writing: ", file_path, " Error: ", FileAccess.get_open_error())
		return false

	file.store_string(json_string)
	file.close()

	print("[WorldStateManager] Saved world state with ", buildables.size(), " buildables")
	return true

func load_world_state() -> Dictionary:
	var file_path = WORLD_STATE_FILE % world_name

	# Check if file exists
	if not FileAccess.file_exists(file_path):
		print("[WorldStateManager] World state not found, starting fresh")
		return {
			"buildables": {},
			"time_of_day": 0.5,
			"global_events": [],
			"last_saved": 0
		}

	# Read file
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[WorldStateManager] Failed to open file for reading: ", file_path, " Error: ", FileAccess.get_open_error())
		return {}

	var json_string = file.get_as_text()
	file.close()

	# Parse JSON
	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_error("[WorldStateManager] Failed to parse world state JSON: ", file_path)
		return {}

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[WorldStateManager] World state is not a dictionary: ", file_path)
		return {}

	# Ensure buildables key exists
	if not data.has("buildables"):
		data["buildables"] = {}

	print("[WorldStateManager] Loaded world state with ", data["buildables"].size(), " buildables")
	return data

func world_state_exists() -> bool:
	var file_path = WORLD_STATE_FILE % world_name
	return FileAccess.file_exists(file_path)
