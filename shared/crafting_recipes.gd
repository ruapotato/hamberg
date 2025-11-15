extends Node

## CraftingRecipes - Central database of all crafting recipes
## Valheim-style crafting system

# Recipe structure:
# {
#   "output_item": "item_name",
#   "output_amount": 1,
#   "requirements": {"item1": amount1, "item2": amount2, ...},
#   "crafting_station": "workbench" (optional - if not specified, can craft anywhere)
# }

var recipes: Array[Dictionary] = []

func _ready() -> void:
	_initialize_recipes()

func _initialize_recipes() -> void:
	recipes.clear()

	# Basic starting tools (no workbench required)
	add_recipe("wooden_club", 1, {"wood": 10})
	add_recipe("hammer", 1, {"wood": 10})
	add_recipe("torch", 1, {"wood": 1, "resin": 1})
	# Note: workbench is now buildable via hammer, not craftable

	print("[CraftingRecipes] Initialized %d recipes" % recipes.size())

func add_recipe(output: String, amount: int, requirements: Dictionary, crafting_station: String = "") -> void:
	var recipe = {
		"output_item": output,
		"output_amount": amount,
		"requirements": requirements
	}

	if not crafting_station.is_empty():
		recipe["crafting_station"] = crafting_station

	recipes.append(recipe)

## Get all craftable recipes (that the player has resources for)
func get_craftable_recipes(inventory: Node) -> Array[Dictionary]:
	var craftable: Array[Dictionary] = []

	for recipe in recipes:
		if can_craft(recipe, inventory):
			craftable.append(recipe)

	return craftable

## Get all recipes, regardless of whether player can craft them
func get_all_recipes() -> Array[Dictionary]:
	return recipes.duplicate()

## Check if a recipe can be crafted with current inventory
## nearby_stations: Array of crafting station names the player is near (e.g., ["workbench"])
func can_craft(recipe: Dictionary, inventory: Node, nearby_stations: Array = []) -> bool:
	if not inventory or not inventory.has_method("has_item"):
		return false

	# Check if crafting station is required
	var required_station: String = recipe.get("crafting_station", "")
	if not required_station.is_empty():
		if not nearby_stations.has(required_station):
			return false  # Missing required crafting station

	var requirements: Dictionary = recipe.get("requirements", {})

	for item_name in requirements:
		var required_amount: int = requirements[item_name]
		if not inventory.has_item(item_name, required_amount):
			return false

	return true

## Attempt to craft an item
## Returns true if successful, false if not enough resources or missing crafting station
func craft_item(recipe: Dictionary, inventory: Node, nearby_stations: Array = []) -> bool:
	if not can_craft(recipe, inventory, nearby_stations):
		return false

	# Remove requirements from inventory
	var requirements: Dictionary = recipe.get("requirements", {})
	for item_name in requirements:
		var required_amount: int = requirements[item_name]
		if not inventory.remove_item(item_name, required_amount):
			# This shouldn't happen if can_craft returned true
			push_error("[CraftingRecipes] Failed to remove %s x%d" % [item_name, required_amount])
			return false

	# Add crafted item to inventory
	var output_item: String = recipe.get("output_item", "")
	var output_amount: int = recipe.get("output_amount", 1)
	var remaining = inventory.add_item(output_item, output_amount)

	if remaining > 0:
		push_warning("[CraftingRecipes] Inventory full! Lost %d x %s" % [remaining, output_item])

	print("[CraftingRecipes] Crafted %d x %s" % [output_amount - remaining, output_item])
	return true

## Get a nice display name for an item (can be customized later)
func get_item_display_name(item_name: String) -> String:
	# Convert snake_case to Title Case
	var words = item_name.split("_")
	var display_name = ""
	for word in words:
		if display_name != "":
			display_name += " "
		display_name += word.capitalize()
	return display_name
