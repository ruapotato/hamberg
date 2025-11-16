extends Node
class_name PlayerDataManager

# Manages saving and loading player character data
# Each character is stored as a JSON file in user://worlds/{world_name}/players/{character_id}.json

const PLAYERS_DIR = "user://worlds/%s/players"
const PLAYER_FILE = "user://worlds/%s/players/%s.json"

var world_name: String = ""

func _init(p_world_name: String = ""):
	world_name = p_world_name

func initialize(p_world_name: String) -> void:
	world_name = p_world_name
	_ensure_players_directory()

func _ensure_players_directory() -> void:
	var dir_path = PLAYERS_DIR % world_name
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
		print("[PlayerDataManager] Created players directory: ", dir_path)

func save_player_data(character_id: String, player_data: Dictionary) -> bool:
	var file_path = PLAYER_FILE % [world_name, character_id]

	# Add timestamp
	player_data["last_played"] = Time.get_unix_time_from_system()

	# Validate required fields
	if not player_data.has("character_name"):
		push_error("[PlayerDataManager] Missing character_name in player data")
		return false

	if not player_data.has("created_at"):
		player_data["created_at"] = Time.get_unix_time_from_system()

	# Serialize to JSON
	var json_string = JSON.stringify(player_data, "\t")

	# Write to file
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("[PlayerDataManager] Failed to open file for writing: ", file_path, " Error: ", FileAccess.get_open_error())
		return false

	file.store_string(json_string)
	file.close()

	print("[PlayerDataManager] Saved player data: ", character_id)
	return true

func load_player_data(character_id: String) -> Dictionary:
	var file_path = PLAYER_FILE % [world_name, character_id]

	# Check if file exists
	if not FileAccess.file_exists(file_path):
		print("[PlayerDataManager] Player data not found: ", character_id)
		return {}

	# Read file
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("[PlayerDataManager] Failed to open file for reading: ", file_path, " Error: ", FileAccess.get_open_error())
		return {}

	var json_string = file.get_as_text()
	file.close()

	# Parse JSON
	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_error("[PlayerDataManager] Failed to parse player data JSON: ", file_path)
		return {}

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[PlayerDataManager] Player data is not a dictionary: ", file_path)
		return {}

	print("[PlayerDataManager] Loaded player data: ", character_id)
	return data

func character_exists(character_id: String) -> bool:
	var file_path = PLAYER_FILE % [world_name, character_id]
	return FileAccess.file_exists(file_path)

func get_all_characters() -> Array[Dictionary]:
	var characters: Array[Dictionary] = []
	var dir_path = PLAYERS_DIR % world_name

	if not DirAccess.dir_exists_absolute(dir_path):
		return characters

	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_error("[PlayerDataManager] Failed to open players directory: ", dir_path)
		return characters

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var character_id = file_name.trim_suffix(".json")
			var data = load_player_data(character_id)

			if not data.is_empty():
				# Add character_id to the data
				data["character_id"] = character_id
				characters.append(data)

		file_name = dir.get_next()

	dir.list_dir_end()

	# Sort by last_played (most recent first)
	characters.sort_custom(func(a, b): return a.get("last_played", 0) > b.get("last_played", 0))

	print("[PlayerDataManager] Found ", characters.size(), " characters")
	return characters

func create_new_character(character_name: String) -> Dictionary:
	# Generate unique character ID
	var character_id = _generate_character_id(character_name)

	# Create default character data
	var player_data = {
		"character_id": character_id,
		"character_name": character_name,
		"position": [0.0, 10.0, 0.0],  # Spawn point
		"rotation_y": 0.0,
		"inventory": [],  # Will be populated with 30 empty slots
		"equipment": {},  # Will be populated with empty equipment slots
		"health": 100.0,
		"max_health": 100.0,
		"created_at": Time.get_unix_time_from_system(),
		"last_played": Time.get_unix_time_from_system(),
		"play_time": 0
	}

	# Initialize empty inventory (30 slots)
	for i in range(30):
		player_data["inventory"].append({})

	# Initialize empty equipment (5 slots: main_hand, off_hand, head, chest, legs)
	# Equipment uses enum values as keys (0-4)
	for i in range(5):
		player_data["equipment"][i] = ""

	# Save to disk
	if save_player_data(character_id, player_data):
		return player_data
	else:
		return {}

func _generate_character_id(character_name: String) -> String:
	# Create a unique ID based on name + timestamp
	var timestamp = Time.get_unix_time_from_system()
	var sanitized_name = character_name.to_lower().replace(" ", "_")
	sanitized_name = sanitized_name.substr(0, 16)  # Limit length
	return "%s_%d" % [sanitized_name, timestamp]

func delete_character(character_id: String) -> bool:
	var file_path = PLAYER_FILE % [world_name, character_id]

	if not FileAccess.file_exists(file_path):
		return false

	var dir = DirAccess.open("user://")
	if dir.remove(file_path) == OK:
		print("[PlayerDataManager] Deleted character: ", character_id)
		return true
	else:
		push_error("[PlayerDataManager] Failed to delete character: ", character_id)
		return false

# Helper to convert player node to saveable data
static func serialize_player(player: Node) -> Dictionary:
	var data = {
		"character_name": player.player_name if "player_name" in player else "Unknown",
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"rotation_y": player.rotation.y,
		"inventory": [],
		"equipment": {},
		"health": 100.0,  # Will be updated when health system exists
		"max_health": 100.0
	}

	# Serialize inventory if exists
	if player.has_node("Inventory"):
		var inventory = player.get_node("Inventory")
		data["inventory"] = inventory.get_inventory_data()
	else:
		# Empty inventory
		for i in range(30):
			data["inventory"].append({})

	# Serialize equipment if exists
	if player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		data["equipment"] = equipment.get_equipment_data()

	return data

# Helper to apply loaded data to player node
static func deserialize_player(player: Node, data: Dictionary) -> void:
	# Set position
	if data.has("position"):
		var pos = data["position"]
		player.global_position = Vector3(pos[0], pos[1], pos[2])

	# Set rotation
	if data.has("rotation_y"):
		player.rotation.y = data["rotation_y"]

	# Set inventory
	if data.has("inventory") and player.has_node("Inventory"):
		var inventory = player.get_node("Inventory")
		inventory.set_inventory_data(data["inventory"])

	# Set equipment
	if data.has("equipment") and player.has_node("Equipment"):
		var equipment = player.get_node("Equipment")
		equipment.set_equipment_data(data["equipment"])

	# Set health (when implemented)
	# if data.has("health"):
	#     player.health = data["health"]
