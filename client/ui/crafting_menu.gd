extends Control

## CraftingMenu - Shows available recipes at a workbench
## Filters recipes based on discovered items (items the player has touched)
## Opens when player presses E on a workbench

signal recipe_crafted(recipe: Dictionary)
signal menu_closed()

var is_open: bool = false
var player_inventory: Node = null  # Reference to player's inventory
var item_discovery_tracker: Node = null  # Reference to discovery tracker
var selected_index: int = 0  # For controller D-pad navigation

@onready var panel: Panel = $Panel
@onready var recipe_list: VBoxContainer = $Panel/ScrollContainer/RecipeList
@onready var scroll_container: ScrollContainer = $Panel/ScrollContainer

func _ready() -> void:
	hide_menu()

## Set the player inventory reference
func set_player_inventory(inventory: Node) -> void:
	player_inventory = inventory

## Set the item discovery tracker reference
func set_discovery_tracker(tracker: Node) -> void:
	item_discovery_tracker = tracker

## Populate the recipe list with discovered recipes
func _populate_recipe_list() -> void:
	if not recipe_list:
		push_error("[CraftingMenu] recipe_list is null!")
		return

	# Clear existing buttons
	for child in recipe_list.get_children():
		child.queue_free()

	# Get discovered recipes from tracker
	var discovered_recipes: Array[Dictionary] = []
	if item_discovery_tracker and item_discovery_tracker.has_method("get_discovered_recipes"):
		discovered_recipes = item_discovery_tracker.get_discovered_recipes()
	else:
		# Fallback: show all recipes
		discovered_recipes = CraftingRecipes.get_all_recipes()

	print("[CraftingMenu] Showing %d discovered recipes" % discovered_recipes.size())

	# Create button for each recipe
	for recipe in discovered_recipes:
		var recipe_name: String = recipe.get("output_item", "")
		if recipe_name.is_empty():
			continue

		# Create a recipe entry
		var recipe_button = _create_recipe_button(recipe)
		recipe_list.add_child(recipe_button)

	if recipe_list.get_child_count() == 0:
		# Show a message if no recipes are available
		var label = Label.new()
		label.text = "No recipes available.\nGather resources to discover new recipes!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		recipe_list.add_child(label)

## Create a button for a recipe
func _create_recipe_button(recipe: Dictionary) -> Control:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(0, 60)

	# Main button
	var button = Button.new()
	button.custom_minimum_size = Vector2(300, 40)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Get recipe info
	var recipe_name: String = recipe.get("output_item", "")
	var output_amount: int = recipe.get("output_amount", 1)
	var requirements: Dictionary = recipe.get("requirements", {})

	# Format display name
	var item_data = ItemDatabase.get_item(recipe_name)
	var display_name = item_data.display_name if item_data else CraftingRecipes.get_item_display_name(recipe_name)

	# Build button text
	var button_text = "%s" % display_name
	if output_amount > 1:
		button_text += " x%d" % output_amount

	button.text = button_text

	# Check if player can craft this
	var can_craft = false
	if player_inventory and CraftingRecipes.can_craft(recipe, player_inventory, ["workbench"]):
		can_craft = true
		button.disabled = false
	else:
		button.disabled = true

	# Connect button
	button.pressed.connect(_on_recipe_button_pressed.bind(recipe))

	container.add_child(button)

	# Add requirements label (use RichTextLabel for colored text)
	var req_label = RichTextLabel.new()
	req_label.custom_minimum_size = Vector2(300, 20)
	req_label.fit_content = true
	req_label.bbcode_enabled = true
	req_label.scroll_active = false
	req_label.add_theme_font_size_override("normal_font_size", 10)

	var req_text = "Requires: "
	var req_parts: Array = []
	for item_name in requirements.keys():
		var amount = requirements[item_name]
		var item_display = ItemDatabase.get_item(item_name)
		var item_name_display = item_display.display_name if item_display else CraftingRecipes.get_item_display_name(item_name)
		var current_amount = 0
		if player_inventory and player_inventory.has_method("get_item_count"):
			current_amount = player_inventory.get_item_count(item_name)

		var color = "[color=green]" if current_amount >= amount else "[color=red]"
		req_parts.append("%s%s x%d[/color] (%d)" % [color, item_name_display, amount, current_amount])

	req_label.text = req_text + ", ".join(req_parts)
	container.add_child(req_label)

	return container

func _on_recipe_button_pressed(recipe: Dictionary) -> void:
	print("[CraftingMenu] Crafting: %s" % recipe.get("output_item", ""))

	# Attempt to craft on server (server-authoritative)
	var recipe_name = recipe.get("output_item", "")
	NetworkManager.rpc_request_craft.rpc_id(1, recipe_name)

	# Close menu after crafting
	hide_menu()

## Show the crafting menu
func show_menu() -> void:
	if is_open:
		return

	# Refresh the recipe list
	_populate_recipe_list()

	selected_index = 0
	_update_selection_visual()

	is_open = true
	visible = true

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("[CraftingMenu] Opened - Select a recipe to craft")

## Hide the crafting menu
func hide_menu() -> void:
	if not is_open:
		return

	is_open = false
	visible = false

	# Recapture mouse for FPS controls
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	menu_closed.emit()

## Toggle menu visibility
func toggle_menu() -> void:
	if is_open:
		hide_menu()
	else:
		show_menu()

func _process(_delta: float) -> void:
	if not is_open:
		return

	# Close menu with Escape or B button
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("jump"):
		hide_menu()
		return

	# D-pad navigation
	if Input.is_action_just_pressed("hotbar_unequip"):  # D-pad Down
		_move_selection(1)
	elif Input.is_action_just_pressed("hotbar_equip"):  # D-pad Up
		_move_selection(-1)

	# A button to craft selected recipe
	if Input.is_action_just_pressed("interact"):
		_craft_selected_recipe()

## Move selection up/down (controller D-pad)
func _move_selection(direction: int) -> void:
	var containers = recipe_list.get_children()
	if containers.is_empty():
		return

	selected_index += direction

	# Wrap around
	if selected_index < 0:
		selected_index = containers.size() - 1
	elif selected_index >= containers.size():
		selected_index = 0

	_update_selection_visual()
	_scroll_to_selected()

## Update visual highlight for selected recipe
func _update_selection_visual() -> void:
	if not recipe_list:
		return

	var containers = recipe_list.get_children()
	for i in containers.size():
		var container = containers[i]
		# Find the button in the container
		for child in container.get_children():
			if child is Button:
				if i == selected_index:
					child.modulate = Color(1.5, 1.5, 1.0)  # Highlight selected
					child.grab_focus()
				else:
					child.modulate = Color.WHITE  # Normal
				break

## Scroll to show the selected recipe
func _scroll_to_selected() -> void:
	if not scroll_container or not recipe_list:
		return

	var containers = recipe_list.get_children()
	if selected_index < 0 or selected_index >= containers.size():
		return

	var selected_container = containers[selected_index]
	if selected_container:
		# Calculate the position to scroll to
		var container_pos = selected_container.position.y
		var container_height = selected_container.size.y
		var scroll_height = scroll_container.size.y

		# Center the selected item in the scroll view
		var target_scroll = container_pos - (scroll_height / 2.0) + (container_height / 2.0)
		scroll_container.scroll_vertical = int(max(0, target_scroll))

## Craft the currently selected recipe (controller A button)
func _craft_selected_recipe() -> void:
	var containers = recipe_list.get_children()
	if selected_index < 0 or selected_index >= containers.size():
		return

	var container = containers[selected_index]
	# Find the button in the container
	for child in container.get_children():
		if child is Button and not child.disabled:
			child.pressed.emit()
			break
