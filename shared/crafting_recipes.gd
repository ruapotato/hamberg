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

# Building piece costs (separate from crafting recipes)
const BUILDING_COSTS: Dictionary = {
	"workbench": {"wood": 10},
	"chest": {"wood": 10},
	"wooden_wall": {"wood": 4},
	"wooden_floor": {"wood": 2},
	"wooden_door": {"wood": 4},
	"wooden_beam": {"wood": 2},
	"wooden_roof_26": {"wood": 2},
	"wooden_roof_45": {"wood": 2},
	"wooden_stairs": {"wood": 4},
}

func _initialize_recipes() -> void:
	recipes.clear()

	# Basic starting tools (no workbench required - shown in Tab menu)
	add_recipe("hammer", 1, {"wood": 10})
	add_recipe("torch", 1, {"wood": 1, "resin": 1})
	add_recipe("club", 1, {"wood": 6})
	add_recipe("fireplace", 1, {"stone": 5, "wood": 2})

	# Tools (workbench required)
	add_recipe("stone_pickaxe", 1, {"wood": 5, "stone": 10}, "workbench")
	add_recipe("stone_hoe", 1, {"wood": 5, "stone": 5}, "workbench")

	# Tier 1 Weapons - Wood & Stone (workbench required)
	add_recipe("stone_sword", 1, {"wood": 10, "stone": 5}, "workbench")
	add_recipe("stone_axe", 1, {"wood": 20, "stone": 10}, "workbench")
	add_recipe("stone_knife", 1, {"wood": 5, "stone": 2}, "workbench")
	add_recipe("fire_wand", 1, {"wood": 3, "resin": 7}, "workbench")
	add_recipe("bow", 1, {"wood": 10, "resin": 1}, "workbench")

	# Shields (workbench required)
	add_recipe("tower_shield", 1, {"wood": 15}, "workbench")
	add_recipe("round_shield", 1, {"wood": 10}, "workbench")
	add_recipe("buckler", 1, {"wood": 5}, "workbench")

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

func get_recipe_by_name(item_name: String) -> Dictionary:
	for recipe in recipes:
		if recipe.get("output_item") == item_name:
			return recipe
	return {}

## Get all craftable recipes (that the player has resources for)
## inventory can be Node (Inventory) or RefCounted (CombinedInventory)
func get_craftable_recipes(inventory) -> Array[Dictionary]:
	var craftable: Array[Dictionary] = []

	for recipe in recipes:
		if can_craft(recipe, inventory):
			craftable.append(recipe)

	return craftable

## Get all recipes, regardless of whether player can craft them
func get_all_recipes() -> Array[Dictionary]:
	return recipes.duplicate()

## Get basic recipes (no crafting station required - shown in Tab menu)
func get_basic_recipes() -> Array[Dictionary]:
	var basic: Array[Dictionary] = []
	for recipe in recipes:
		var station: String = recipe.get("crafting_station", "")
		if station.is_empty():
			basic.append(recipe)
	return basic

## Check if a recipe can be crafted with current inventory
## inventory can be Node (Inventory) or RefCounted (CombinedInventory)
## nearby_stations: Array of crafting station names the player is near (e.g., ["workbench"])
func can_craft(recipe: Dictionary, inventory, nearby_stations: Array = []) -> bool:
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
## inventory can be Node (Inventory) or RefCounted (CombinedInventory)
## Returns true if successful, false if not enough resources or missing crafting station
func craft_item(recipe: Dictionary, inventory, nearby_stations: Array = []) -> bool:
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
