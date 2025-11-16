extends Node

## ItemDiscoveryTracker - Client-side tracking of discovered items
## Tracks what item types the player has touched/picked up
## Used to filter crafting recipes to show only items with discovered materials

# Set of discovered item IDs
var discovered_items: Dictionary = {}  # item_id -> bool

# Signal emitted when a new item is discovered
signal item_discovered(item_id: String)
signal recipes_unlocked(recipe_names: Array)

var character_name: String = ""  # Current character name
const SAVE_DIR = "user://discoveries/"

func _ready() -> void:
	# Create save directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

## Set the current character name and load their discoveries
func set_character(char_name: String) -> void:
	character_name = char_name
	_load_discoveries()
	print("[ItemDiscoveryTracker] Loaded %d discovered items for character '%s'" % [discovered_items.size(), character_name])

## Mark an item as discovered
func discover_item(item_id: String) -> void:
	if not discovered_items.has(item_id):
		discovered_items[item_id] = true
		print("[ItemDiscoveryTracker] Discovered new item: %s" % item_id)
		item_discovered.emit(item_id)

		# Check for newly unlocked recipes
		_check_for_unlocked_recipes(item_id)

		# Save discoveries
		_save_discoveries()

## Check if an item has been discovered
func is_discovered(item_id: String) -> bool:
	return discovered_items.has(item_id)

## Get all discovered item IDs
func get_discovered_items() -> Array:
	return discovered_items.keys()

## Check if all requirements for a recipe are discovered
func are_all_requirements_discovered(recipe: Dictionary) -> bool:
	var requirements: Dictionary = recipe.get("requirements", {})

	for item_id in requirements.keys():
		if not is_discovered(item_id):
			return false

	return true

## Get all craftable recipes based on discovered items
func get_discovered_recipes() -> Array[Dictionary]:
	var all_recipes = CraftingRecipes.get_all_recipes()
	var discovered_recipes: Array[Dictionary] = []

	for recipe in all_recipes:
		if are_all_requirements_discovered(recipe):
			discovered_recipes.append(recipe)

	return discovered_recipes

## Check for newly unlocked recipes after discovering an item
func _check_for_unlocked_recipes(newly_discovered_item: String) -> void:
	var all_recipes = CraftingRecipes.get_all_recipes()
	var newly_unlocked: Array = []

	for recipe in all_recipes:
		# Check if this recipe uses the newly discovered item
		var requirements: Dictionary = recipe.get("requirements", {})
		if not requirements.has(newly_discovered_item):
			continue

		# Check if ALL requirements are now discovered
		if are_all_requirements_discovered(recipe):
			var recipe_name = recipe.get("output_item", "")
			newly_unlocked.append(recipe_name)

	# Emit signal with newly unlocked recipes
	if newly_unlocked.size() > 0:
		recipes_unlocked.emit(newly_unlocked)

## Save discoveries to disk
func _save_discoveries() -> void:
	if character_name.is_empty():
		push_warning("[ItemDiscoveryTracker] No character name set, not saving")
		return

	var save_path = SAVE_DIR + character_name + "_discoveries.save"
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var data = {
			"discovered_items": discovered_items.keys()
		}
		file.store_var(data)
		file.close()
		print("[ItemDiscoveryTracker] Saved %d discovered items for '%s'" % [discovered_items.size(), character_name])
	else:
		push_error("[ItemDiscoveryTracker] Failed to save discoveries")

## Load discoveries from disk
func _load_discoveries() -> void:
	discovered_items.clear()

	if character_name.is_empty():
		print("[ItemDiscoveryTracker] No character name set, skipping load")
		return

	var save_path = SAVE_DIR + character_name + "_discoveries.save"
	if not FileAccess.file_exists(save_path):
		print("[ItemDiscoveryTracker] No save file found for '%s', starting fresh" % character_name)
		return

	var file = FileAccess.open(save_path, FileAccess.READ)
	if file:
		var data = file.get_var()
		file.close()

		if data is Dictionary:
			var item_list = data.get("discovered_items", [])
			for item_id in item_list:
				discovered_items[item_id] = true
			print("[ItemDiscoveryTracker] Loaded %d discovered items for '%s'" % [discovered_items.size(), character_name])
	else:
		push_error("[ItemDiscoveryTracker] Failed to load discoveries")

## Reset all discoveries (for testing or new game)
func reset_discoveries() -> void:
	discovered_items.clear()
	_save_discoveries()
	print("[ItemDiscoveryTracker] Reset all discoveries")
