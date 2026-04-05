extends Control

## TaskMenu - Guided progression task list
## Shows tasks that the player should complete, checks them off automatically.
## Toggle with Tab key. Displays in top-left corner, semi-transparent.

# Task definition: {id, description, check_func_name}
const TASKS: Array[Dictionary] = [
	{"id": "collect_wood", "description": "Punch bushes to collect wood"},
	{"id": "collect_stone", "description": "Punch rocks to collect stone"},
	{"id": "craft_stone_axe", "description": "Craft a Stone Axe (4 wood + 4 stone)"},
	{"id": "chop_tree", "description": "Chop down a tree with your axe"},
	{"id": "build_workbench", "description": "Build a Workbench (10 wood)"},
	{"id": "craft_stone_knife", "description": "Craft a Stone Knife at the Workbench"},
	{"id": "build_shelter", "description": "Build walls and a roof for shelter"},
	{"id": "build_fireplace", "description": "Build a Fireplace (5 stone, 2 wood)"},
	{"id": "cook_meat", "description": "Hunt an animal and cook the meat"},
	{"id": "craft_fire_wand", "description": "Craft a Fire Wand at the Workbench"},
	{"id": "survive_first_night", "description": "Survive the first night"},
]

# Tracking
var completed_tasks: Dictionary = {}  # task_id -> bool
var player_ref: Node3D = null
var _panel: PanelContainer = null
var _vbox: VBoxContainer = null
var _task_labels: Array[Label] = []
var _title_label: Label = null
var _is_visible: bool = false
var _day_count: int = 1  # Track what day we're on


func _ready() -> void:
	# Build the UI programmatically
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Full-screen anchor so we can position in top-left
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Position in top-left
	_panel.anchors_preset = PRESET_TOP_LEFT
	_panel.offset_left = 10.0
	_panel.offset_top = 10.0
	_panel.offset_right = 320.0
	_panel.offset_bottom = 400.0

	# Semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)

	add_child(_panel)

	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_theme_constant_override("separation", 4)
	margin.add_child(_vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "== Tasks =="
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_title_label.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(_title_label)

	# Separator
	var sep = HSeparator.new()
	_vbox.add_child(sep)

	# Create labels for each task
	for i in range(TASKS.size()):
		var task = TASKS[i]
		var label = Label.new()
		label.text = "%d. %s" % [i + 1, task["description"]]
		label.add_theme_font_size_override("font_size", 14)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(label)
		_task_labels.append(label)

	# Start visible so players see tasks immediately (Tab to hide)
	_panel.visible = true
	_is_visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_visibility()
			get_viewport().set_input_as_handled()


func _toggle_visibility() -> void:
	_is_visible = not _is_visible
	_panel.visible = _is_visible


## Set the player reference for checking inventory/state
func set_player(player: Node3D) -> void:
	player_ref = player


## Call periodically to check task completion
func check_tasks() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		return

	var inventory = player_ref.get_node_or_null("Inventory")

	for i in range(TASKS.size()):
		var task = TASKS[i]
		var task_id = task["id"]

		if completed_tasks.get(task_id, false):
			continue  # Already complete

		var is_complete = _check_task(task_id, inventory)
		if is_complete:
			completed_tasks[task_id] = true
			print("[TaskMenu] Task completed: %s" % task["description"])

	_update_display()


func _check_task(task_id: String, inventory: Node) -> bool:
	match task_id:
		"collect_wood":
			return inventory and inventory.has_item("wood", 1)
		"collect_stone":
			return inventory and inventory.has_item("stone", 1)
		"craft_stone_axe":
			return inventory and inventory.has_item("stone_axe", 1)
		"chop_tree":
			# Check if player has more than 5 wood (means they chopped a tree, not just bushes)
			return inventory and inventory.has_item("wood", 8)
		"build_workbench":
			var workbenches = get_tree().get_nodes_in_group("workbenches")
			return workbenches.size() > 0
		"craft_stone_knife":
			return inventory and inventory.has_item("stone_knife", 1)
		"build_shelter":
			# Check if player has placed both wall and roof pieces
			var has_wall = false
			var has_roof = false
			for node in get_tree().get_nodes_in_group("crafting_stations"):
				pass  # Crafting stations aren't walls/roofs
			# Check world for buildable walls and roofs
			var world_node = get_tree().root.get_node_or_null("Main/Client/World")
			if world_node:
				for child in world_node.get_children():
					var cname = child.name.to_lower()
					if "wall" in cname:
						has_wall = true
					if "roof" in cname:
						has_roof = true
			return has_wall and has_roof
		"build_fireplace":
			var world_node = get_tree().root.get_node_or_null("Main/Client/World")
			if world_node:
				for child in world_node.get_children():
					if "fireplace" in child.name.to_lower() or "fire_pit" in child.name.to_lower() or "campfire" in child.name.to_lower() or "cooking" in child.name.to_lower():
						return true
			return false
		"cook_meat":
			if not inventory:
				return false
			return inventory.has_item("cooked_venison", 1) or inventory.has_item("cooked_pork", 1) or inventory.has_item("cooked_mutton", 1) or inventory.has_item("cooked_meat", 1)
		"craft_fire_wand":
			return inventory and inventory.has_item("fire_wand", 1)
		"survive_first_night":
			return _day_count >= 2
	return false


func _update_display() -> void:
	# Find the first incomplete task (active task)
	var active_index = -1
	for i in range(TASKS.size()):
		if not completed_tasks.get(TASKS[i]["id"], false):
			active_index = i
			break

	for i in range(TASKS.size()):
		var task = TASKS[i]
		var label = _task_labels[i]
		var is_done = completed_tasks.get(task["id"], false)

		if is_done:
			# Green with checkmark
			label.text = "[OK] %d. %s" % [i + 1, task["description"]]
			label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3, 0.8))
		elif i == active_index:
			# Current active task - highlighted yellow
			label.text = ">> %d. %s" % [i + 1, task["description"]]
			label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5, 1.0))
		else:
			# Future task - dimmed
			label.text = "   %d. %s" % [i + 1, task["description"]]
			label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))


## Track day changes (called by client when day/night cycle advances)
func advance_day() -> void:
	_day_count += 1
	print("[TaskMenu] Day %d started" % _day_count)


## Get task progress as a dictionary (for saving)
func get_progress_data() -> Dictionary:
	return {
		"completed_tasks": completed_tasks.duplicate(),
		"day_count": _day_count,
	}


## Load task progress from saved data
func load_progress_data(data: Dictionary) -> void:
	if data.has("completed_tasks"):
		completed_tasks = data["completed_tasks"].duplicate()
	if data.has("day_count"):
		_day_count = data["day_count"]
	_update_display()
