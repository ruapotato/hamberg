extends Node

## CraftingRecipes - Central database of all crafting recipes
## Valheim-style crafting system

# Recipe structure:
# {
#   "output_item": "item_name",
#   "output_amount": 1,
#   "requirements": {"item1": amount1, "item2": amount2, ...}
# }

var recipes: Array[Dictionary] = []

func _ready() -> void:
	_initialize_recipes()

func _initialize_recipes() -> void:
	recipes.clear()

	# Basic crafting recipes (similar to Valheim)

	# Tools
	add_recipe("wooden_club", 1, {"wood": 5})
	add_recipe("stone_axe", 1, {"wood": 5, "stone": 4})
	add_recipe("stone_pickaxe", 1, {"wood": 5, "stone": 10})

	# Building materials
	add_recipe("wooden_wall", 1, {"wood": 4})
	add_recipe("wooden_floor", 1, {"wood": 2})
	add_recipe("wooden_door", 1, {"wood": 6})

	# Furniture
	add_recipe("workbench", 1, {"wood": 10})
	add_recipe("storage_chest", 1, {"wood": 10})

	# Advanced materials (when copper and iron are available)
	# add_recipe("copper_bar", 1, {"copper": 5})
	# add_recipe("iron_bar", 1, {"iron": 5})

	print("[CraftingRecipes] Initialized %d recipes" % recipes.size())

func add_recipe(output: String, amount: int, requirements: Dictionary) -> void:
	recipes.append({
		"output_item": output,
		"output_amount": amount,
		"requirements": requirements
	})

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
func can_craft(recipe: Dictionary, inventory: Node) -> bool:
	if not inventory or not inventory.has_method("has_item"):
		return false

	var requirements: Dictionary = recipe.get("requirements", {})

	for item_name in requirements:
		var required_amount: int = requirements[item_name]
		if not inventory.has_item(item_name, required_amount):
			return false

	return true

## Attempt to craft an item
## Returns true if successful, false if not enough resources
func craft_item(recipe: Dictionary, inventory: Node) -> bool:
	if not can_craft(recipe, inventory):
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
