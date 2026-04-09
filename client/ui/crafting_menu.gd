extends Control

## CraftingMenu - Shows available recipes at a workbench
## Filters recipes based on discovered items (items the player has touched)
## Opens when player presses E on a workbench

signal recipe_crafted(recipe: Dictionary)
signal menu_closed()

const CombinedInventory = preload("res://shared/combined_inventory.gd")
const ItemTooltip = preload("res://client/ui/item_tooltip.gd")
const CHEST_SEARCH_RADIUS: float = 15.0

var is_open: bool = false
var _tooltip_instance: Control = null
var _tooltip_layer: CanvasLayer = null
var _hovered_item: String = ""
var player_inventory: Node = null  # Reference to player's inventory
var item_discovery_tracker: Node = null  # Reference to discovery tracker
var local_player: Node = null  # Reference to local player (for finding nearby chests)
var selected_index: int = 0  # For controller D-pad navigation
var just_opened_frames: int = 0  # Delay before accepting craft input to prevent E key from auto-crafting

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

## Set the local player reference (for finding nearby chests)
func set_local_player(player: Node) -> void:
	local_player = player

## Get all chests within radius of the player (for combined inventory)
func _get_nearby_chests() -> Array:
	if not local_player or not is_instance_valid(local_player):
		return []

	var nearby_chests: Array = []
	var player_pos = local_player.global_position

	# Search for chest nodes in the world
	var world = local_player.get_parent()
	if not world:
		return []

	for child in world.get_children():
		if child.is_in_group("chest") or child.name.begins_with("Chest"):
			if child.has_method("get_item_count"):
				var distance = player_pos.distance_to(child.global_position)
				if distance <= CHEST_SEARCH_RADIUS:
					nearby_chests.append(child)

	return nearby_chests

## Get a combined inventory (player + nearby chests) for crafting display
func _get_combined_inventory():
	var nearby_chests = _get_nearby_chests()
	return CombinedInventory.new(player_inventory, nearby_chests)

## Detect all crafting stations near the player
func _get_nearby_stations() -> Array:
	var stations: Array = []
	if not local_player or not is_instance_valid(local_player):
		return ["workbench"]

	var player_pos: Vector3 = local_player.global_position
	for node in local_player.get_tree().get_nodes_in_group("crafting_stations"):
		if is_instance_valid(node) and node.has_method("is_position_in_range"):
			if node.is_position_in_range(player_pos):
				var st: String = node.get("station_type")
				if st and not stations.has(st):
					stations.append(st)

	# Also check for fireplaces/cooking stations in buildables group
	for node in local_player.get_tree().get_nodes_in_group("buildables"):
		if not is_instance_valid(node):
			continue
		var dist: float = player_pos.distance_to(node.global_position)
		if dist > 20.0:
			continue
		var node_name: String = node.name.to_lower()
		if "fireplace" in node_name or "fire_pit" in node_name or "cooking" in node_name:
			if not stations.has("fireplace"):
				stations.append("fireplace")

	if stations.is_empty():
		stations.append("workbench")
	return stations

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

## Try to load an item icon texture, returns null if not found
func _load_item_icon(item_id: String) -> Texture2D:
	var icon_path = "res://images/icons/%s.png" % item_id
	if ResourceLoader.exists(icon_path):
		return load(icon_path)
	return null

## Create a button for a recipe
func _create_recipe_button(recipe: Dictionary) -> Control:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(0, 68)

	# Get recipe info
	var recipe_name: String = recipe.get("output_item", "")
	var output_amount: int = recipe.get("output_amount", 1)
	var requirements: Dictionary = recipe.get("requirements", {})

	# Format display name
	var item_data = ItemDatabase.get_item(recipe_name)
	var display_name = item_data.display_name if item_data else CraftingRecipes.get_item_display_name(recipe_name)

	# Main button with icon inside
	var button = Button.new()
	button.custom_minimum_size = Vector2(340, 44)

	# HBoxContainer inside button for icon + text layout
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	hbox.offset_left = 6.0
	hbox.offset_top = 4.0
	hbox.offset_right = -6.0
	hbox.offset_bottom = -4.0
	button.add_child(hbox)

	# Output item icon
	var icon_tex = _load_item_icon(recipe_name)
	if icon_tex:
		var icon_rect = TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(36, 36)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon_rect)

	# Name label
	var name_label = Label.new()
	var button_text = display_name
	if output_amount > 1:
		button_text += " x%d" % output_amount
	name_label.text = button_text
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	# Leave button text empty since we use the hbox content
	button.text = ""

	# Get combined inventory (player + nearby chests) for crafting check
	var combined_inventory = _get_combined_inventory()

	# Check if player can craft this (using combined inventory)
	var can_craft = false
	if combined_inventory and CraftingRecipes.can_craft(recipe, combined_inventory, _get_nearby_stations()):
		can_craft = true
		button.disabled = false
	else:
		button.disabled = true

	# Connect button
	button.pressed.connect(_on_recipe_button_pressed.bind(recipe))
	button.mouse_entered.connect(_on_recipe_mouse_entered.bind(recipe_name))
	button.mouse_exited.connect(_on_recipe_mouse_exited)

	container.add_child(button)

	# Requirements row with icons
	var req_hbox = HBoxContainer.new()
	req_hbox.add_theme_constant_override("separation", 4)
	req_hbox.custom_minimum_size = Vector2(340, 22)

	var requires_label = Label.new()
	requires_label.text = "Needs: "
	requires_label.add_theme_font_size_override("font_size", 10)
	requires_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	req_hbox.add_child(requires_label)

	for item_name in requirements.keys():
		var amount = requirements[item_name]
		var current_amount = 0
		if combined_inventory and combined_inventory.has_method("get_item_count"):
			current_amount = combined_inventory.get_item_count(item_name)

		# Ingredient icon
		var ing_icon = _load_item_icon(item_name)
		if ing_icon:
			var ing_rect = TextureRect.new()
			ing_rect.texture = ing_icon
			ing_rect.custom_minimum_size = Vector2(18, 18)
			ing_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			ing_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			req_hbox.add_child(ing_rect)

		# Amount text (colored)
		var amt_label = Label.new()
		amt_label.text = "%d/%d" % [current_amount, amount]
		amt_label.add_theme_font_size_override("font_size", 10)
		if current_amount >= amount:
			amt_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		else:
			amt_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		req_hbox.add_child(amt_label)

	container.add_child(req_hbox)

	return container

func _on_recipe_button_pressed(recipe: Dictionary) -> void:
	print("[CraftingMenu] Crafting: %s" % recipe.get("output_item", ""))

	SoundManager.play_ui_sound("ui_confirm")

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
	just_opened_frames = 2  # Wait 2 frames before accepting craft input (prevents E key from auto-crafting)

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	SoundManager.play_ui_sound("menu_open")
	print("[CraftingMenu] Opened - Select a recipe to craft")

## Hide the crafting menu
func hide_menu() -> void:
	if not is_open:
		return

	is_open = false
	visible = false
	_hide_tooltip()
	_hovered_item = ""

	SoundManager.play_ui_sound("menu_close")

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

	# Update tooltip position
	if _hovered_item != "" and _tooltip_instance and _tooltip_instance.visible:
		_update_tooltip_position()

	# Decrement the frame delay counter
	if just_opened_frames > 0:
		just_opened_frames -= 1

	# Close menu with Escape or B button
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("jump"):
		hide_menu()
		return

	# D-pad navigation
	if Input.is_action_just_pressed("hotbar_unequip"):  # D-pad Down
		_move_selection(1)
	elif Input.is_action_just_pressed("hotbar_equip"):  # D-pad Up
		_move_selection(-1)

	# A button to craft selected recipe (only if not just opened)
	if just_opened_frames == 0 and Input.is_action_just_pressed("interact"):
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

## Called when mouse enters a recipe button
func _on_recipe_mouse_entered(item_id: String) -> void:
	_hovered_item = item_id
	_show_tooltip(item_id)

## Called when mouse exits a recipe button
func _on_recipe_mouse_exited() -> void:
	_hovered_item = ""
	_hide_tooltip()

## Show tooltip for an item
func _show_tooltip(item_id: String) -> void:
	if item_id.is_empty():
		return

	# Create tooltip if needed
	if not _tooltip_instance:
		_create_tooltip_instance()

	if _tooltip_instance:
		_tooltip_instance.show_for_item(item_id, get_viewport().get_mouse_position())

## Hide the tooltip
func _hide_tooltip() -> void:
	if _tooltip_instance:
		_tooltip_instance.visible = false

## Create the tooltip instance
func _create_tooltip_instance() -> void:
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 101
	_tooltip_layer.name = "CraftingTooltipLayer"
	get_tree().root.add_child(_tooltip_layer)

	_tooltip_instance = PanelContainer.new()
	_tooltip_instance.set_script(ItemTooltip)
	_tooltip_layer.add_child(_tooltip_instance)
	_tooltip_instance._ready()

## Update tooltip position (called from _process when tooltip visible)
func _update_tooltip_position() -> void:
	if not _tooltip_instance or not _tooltip_instance.visible:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var tooltip_size = _tooltip_instance.size

	var pos = mouse_pos + Vector2(15, 15)

	if pos.x + tooltip_size.x > viewport_size.x:
		pos.x = mouse_pos.x - tooltip_size.x - 10
	if pos.y + tooltip_size.y > viewport_size.y:
		pos.y = viewport_size.y - tooltip_size.y - 10

	_tooltip_instance.global_position = pos
