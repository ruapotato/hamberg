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
	"fireplace": {"stone": 5, "wood": 2},
	"cooking_station": {"stone": 3, "wood": 5},
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
	add_recipe("hammer", 1, {"wood": 5})  # First tool - used to place workbench
	add_recipe("torch", 1, {"wood": 1, "resin": 1})
	add_recipe("bandage", 1, {"plant_fiber": 2})

	# Workbench-required crafting resources
	add_recipe("rope", 1, {"plant_fiber": 3}, "workbench")

	# Tools (workbench required)
	add_recipe("stone_axe", 1, {"wood": 4, "stone": 4}, "workbench")
	add_recipe("stone_pickaxe", 1, {"wood": 5, "stone": 10}, "workbench")
	add_recipe("stone_hoe", 1, {"wood": 5, "stone": 5}, "workbench")

	# Tier 1 Weapons - Wood & Stone (workbench required)
	add_recipe("stone_sword", 1, {"wood": 10, "stone": 5}, "workbench")
	add_recipe("stone_knife", 1, {"wood": 5, "stone": 2}, "workbench")
	add_recipe("fire_wand", 1, {"wood": 3, "resin": 7}, "workbench")
	add_recipe("ice_wand", 1, {"wood": 5, "stone": 5}, "workbench")  # Tier 1 - ice themed
	add_recipe("arcane_wand", 1, {"wood": 5, "stone": 3}, "workbench")  # Tier 1 - cheap
	add_recipe("nature_wand", 1, {"wood": 8, "resin": 5}, "workbench")  # Tier 2 - wood-heavy for nature theme
	add_recipe("holy_wand", 1, {"wood": 5, "stone": 5, "copper": 3}, "workbench")  # Tier 2 - needs some metal
	add_recipe("lightning_wand", 1, {"wood": 5, "copper": 5, "iron": 3}, "workbench")  # Tier 2 - needs metal
	add_recipe("dark_wand", 1, {"wood": 3, "charcoal": 5, "iron": 3}, "workbench")  # Tier 2 - dark materials
	add_recipe("bow", 1, {"wood": 8, "rope": 3}, "workbench")
	add_recipe("arrows", 10, {"wood": 2, "stone": 1}, "workbench")

	# Shields (workbench required)
	add_recipe("tower_shield", 1, {"wood": 15}, "workbench")
	add_recipe("round_shield", 1, {"wood": 10}, "workbench")
	add_recipe("buckler", 1, {"wood": 5}, "workbench")

	# Charcoal (fireplace required)
	add_recipe("charcoal", 3, {"wood": 5}, "fireplace")

	# Cooking biome foods (fireplace required)
	add_recipe("cooked_carrot", 1, {"carrot": 1}, "fireplace")
	add_recipe("cooked_truffle", 1, {"truffle": 1}, "fireplace")
	add_recipe("cooked_frost_berry", 1, {"frost_berry": 2}, "fireplace")
	add_recipe("cooked_prickly_fruit", 1, {"prickly_fruit": 1}, "fireplace")
	add_recipe("cooked_mana_fruit", 1, {"mana_fruit": 1}, "fireplace")
	add_recipe("cooked_ember_pepper", 1, {"ember_pepper": 1}, "fireplace")

	# Tier 2 Weapons - Iron (workbench required)
	add_recipe("iron_sword", 1, {"iron": 3, "wood": 2}, "workbench")
	add_recipe("iron_axe", 1, {"iron": 3, "wood": 2}, "workbench")
	add_recipe("iron_pickaxe", 1, {"iron": 3, "wood": 2}, "workbench")

	# Potions (workbench required)
	add_recipe("healing_potion", 1, {"glowing_spore": 3, "resin": 1}, "workbench")
	add_recipe("stamina_potion", 1, {"fungal_essence": 2, "resin": 1}, "workbench")

	# Biome potions (workbench required)
	add_recipe("antidote_potion", 1, {"marsh_herb": 2, "nightshade_berry": 1}, "workbench")
	add_recipe("mana_potion", 1, {"arcane_herb": 2, "mana_fruit": 1}, "workbench")
	add_recipe("fire_resistance_potion", 1, {"ember_pepper": 2, "brimstone_root": 1}, "workbench")
	add_recipe("frost_resistance_potion", 1, {"frost_berry": 2, "alpine_herb": 1}, "workbench")
	add_recipe("speed_potion", 1, {"desert_sage": 2, "prickly_fruit": 1}, "workbench")

	# Bone Armor Set (workbench required) - mid-tier from zombie drops
	add_recipe("bone_armor_helmet", 1, {"bone": 4, "deer_leather": 2}, "workbench")
	add_recipe("bone_armor_chest", 1, {"bone": 6, "deer_leather": 3}, "workbench")
	add_recipe("bone_armor_legs", 1, {"bone": 5, "deer_leather": 2}, "workbench")
	add_recipe("bone_armor_boots", 1, {"bone": 3, "deer_leather": 2}, "workbench")

	# Pig Armor Set (workbench required) - grants Double Jump when full set worn
	add_recipe("pig_helmet", 1, {"pig_leather": 4}, "workbench")
	add_recipe("pig_chest", 1, {"pig_leather": 6}, "workbench")
	add_recipe("pig_pants", 1, {"pig_leather": 5}, "workbench")
	add_recipe("pig_cape", 1, {"pig_leather": 3}, "workbench")

	# Deer Armor Set (workbench required) - grants 50% Sprint Stamina Reduction when full set worn
	add_recipe("deer_helmet", 1, {"deer_leather": 4}, "workbench")
	add_recipe("deer_chest", 1, {"deer_leather": 6}, "workbench")
	add_recipe("deer_pants", 1, {"deer_leather": 5}, "workbench")
	add_recipe("deer_cape", 1, {"deer_leather": 3}, "workbench")

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
