extends Control

## TaskMenu - Skill Tree Progression UI
## Shows Phase 1 basics then 4 branching paths (Warrior, Ranger, Mage, Survival).
## Toggle with Tab key. Displays in top-left corner, semi-transparent.

# Phase 1 tasks - everyone does these first
const PHASE1_TASKS: Array[Dictionary] = [
	{"id": "collect_wood", "description": "Collect wood", "short": "Collect wood"},
	{"id": "collect_stone", "description": "Collect stone", "short": "Collect stone"},
	{"id": "craft_hammer", "description": "Craft a Hammer", "short": "Craft Hammer"},
	{"id": "place_workbench", "description": "Place a Workbench", "short": "Place Workbench"},
	{"id": "craft_stone_axe", "description": "Craft a Stone Axe", "short": "Craft Stone Axe"},
	{"id": "chop_tree", "description": "Chop a tree", "short": "Chop tree"},
]

# Path definitions: name, color, tasks
const PATHS: Array[Dictionary] = [
	{
		"name": "WARRIOR",
		"color": "ff8800",  # Orange
		"tasks": [
			{"id": "craft_stone_sword", "short": "Sword"},
			{"id": "craft_iron_sword", "short": "Iron Sword"},
			{"id": "craft_tower_shield", "short": "Shield"},
			{"id": "craft_bone_armor_full", "short": "Bone Armor"},
		]
	},
	{
		"name": "RANGER",
		"color": "44cc44",  # Green
		"tasks": [
			{"id": "craft_bow", "short": "Bow"},
			{"id": "craft_arrows", "short": "Arrows"},
			{"id": "craft_stone_knife", "short": "Knife"},
			{"id": "craft_iron_pickaxe", "short": "Iron Pick"},
		]
	},
	{
		"name": "MAGE",
		"color": "4488ff",  # Blue
		"tasks": [
			{"id": "craft_fire_wand", "short": "Fire Wand"},
			{"id": "craft_ice_wand", "short": "Ice Wand"},
			{"id": "craft_lightning_wand", "short": "Bolt Wand"},
			{"id": "craft_arcane_wand", "short": "Arcane"},
		]
	},
	{
		"name": "SURVIVAL",
		"color": "aa7744",  # Brown
		"tasks": [
			{"id": "build_shelter", "short": "Shelter"},
			{"id": "build_fireplace", "short": "Fireplace"},
			{"id": "cook_meat", "short": "Cook Meat"},
			{"id": "survive_first_night", "short": "1st Night"},
		]
	},
]

# Tracking
var completed_tasks: Dictionary = {}  # task_id -> bool
var player_ref: Node3D = null
var _panel: PanelContainer = null
var _vbox: VBoxContainer = null
var _phase1_labels: Array[Label] = []
var _path_header_labels: Array[Label] = []
var _path_task_labels: Array[Array] = []  # Array of Array[Label], one per path
var _title_label: Label = null
var _is_visible: bool = false
var _day_count: int = 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchors_preset = PRESET_TOP_LEFT
	_panel.offset_left = 10.0
	_panel.offset_top = 10.0
	_panel.offset_right = 500.0
	_panel.offset_bottom = 450.0

	# Semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
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
	_vbox.add_theme_constant_override("separation", 2)
	margin.add_child(_vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "PROGRESSION (Tab to hide)"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_title_label.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(_title_label)

	# Separator
	_vbox.add_child(HSeparator.new())

	# Phase 1 tasks
	for task in PHASE1_TASKS:
		var label = Label.new()
		label.text = "[ ] %s" % task["description"]
		label.add_theme_font_size_override("font_size", 14)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(label)
		_phase1_labels.append(label)

	# Separator before paths
	_vbox.add_child(HSeparator.new())

	# Path headers row
	var header_hbox = HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_theme_constant_override("separation", 8)
	_vbox.add_child(header_hbox)

	for path in PATHS:
		var header = Label.new()
		header.text = path["name"]
		header.add_theme_font_size_override("font_size", 14)
		header.add_theme_color_override("font_color", Color(path["color"]))
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_hbox.add_child(header)
		_path_header_labels.append(header)

	# Path task rows (4 rows, one per task tier)
	var max_tasks = 4
	for row_idx in range(max_tasks):
		var row_hbox = HBoxContainer.new()
		row_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_hbox.add_theme_constant_override("separation", 8)
		_vbox.add_child(row_hbox)

		for path_idx in range(PATHS.size()):
			# Ensure we have an array for this path
			while _path_task_labels.size() <= path_idx:
				_path_task_labels.append([])

			var path = PATHS[path_idx]
			var label = Label.new()
			if row_idx < path["tasks"].size():
				var task = path["tasks"][row_idx]
				label.text = "[ ] %s" % task["short"]
			else:
				label.text = ""
			label.add_theme_font_size_override("font_size", 13)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row_hbox.add_child(label)
			_path_task_labels[path_idx].append(label)

	# Start visible
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


func set_player(player: Node3D) -> void:
	player_ref = player


func _is_phase1_complete() -> bool:
	for task in PHASE1_TASKS:
		if not completed_tasks.get(task["id"], false):
			return false
	return true


func check_tasks() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		return

	var inventory = player_ref.get_node_or_null("Inventory")

	# Check Phase 1 tasks
	for task in PHASE1_TASKS:
		var task_id = task["id"]
		if completed_tasks.get(task_id, false):
			continue
		if _check_task(task_id, inventory):
			completed_tasks[task_id] = true
			print("[TaskMenu] Task completed: %s" % task["description"])

	# Check path tasks (only if Phase 1 complete)
	if _is_phase1_complete():
		for path in PATHS:
			for task in path["tasks"]:
				var task_id = task["id"]
				if completed_tasks.get(task_id, false):
					continue
				if _check_task(task_id, inventory):
					completed_tasks[task_id] = true
					print("[TaskMenu] Task completed: %s" % task["short"])

	_update_display()


func _check_task(task_id: String, inventory: Node) -> bool:
	match task_id:
		"collect_wood":
			return inventory and inventory.has_item("wood", 1)
		"collect_stone":
			return inventory and inventory.has_item("stone", 1)
		"craft_hammer":
			return inventory and inventory.has_item("hammer", 1)
		"place_workbench":
			var workbenches = get_tree().get_nodes_in_group("workbenches")
			return workbenches.size() > 0
		"craft_stone_axe":
			return inventory and inventory.has_item("stone_axe", 1)
		"chop_tree":
			return inventory and inventory.has_item("wood", 8)
		# Warrior path
		"craft_stone_sword":
			return inventory and inventory.has_item("stone_sword", 1)
		"craft_iron_sword":
			return inventory and inventory.has_item("iron_sword", 1)
		"craft_tower_shield":
			return inventory and inventory.has_item("tower_shield", 1)
		"craft_bone_armor_full":
			if not inventory:
				return false
			return inventory.has_item("bone_armor_helmet", 1) and inventory.has_item("bone_armor_chest", 1) and inventory.has_item("bone_armor_legs", 1) and inventory.has_item("bone_armor_boots", 1)
		# Ranger path
		"craft_bow":
			return inventory and inventory.has_item("bow", 1)
		"craft_arrows":
			return inventory and inventory.has_item("arrows", 1)
		"craft_stone_knife":
			return inventory and inventory.has_item("stone_knife", 1)
		"craft_iron_pickaxe":
			return inventory and inventory.has_item("iron_pickaxe", 1)
		# Mage path
		"craft_fire_wand":
			return inventory and inventory.has_item("fire_wand", 1)
		"craft_ice_wand":
			return inventory and inventory.has_item("ice_wand", 1)
		"craft_lightning_wand":
			return inventory and inventory.has_item("lightning_wand", 1)
		"craft_arcane_wand":
			return inventory and inventory.has_item("arcane_wand", 1)
		# Survival path
		"build_shelter":
			var has_wall = false
			var has_roof = false
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
		"survive_first_night":
			return _day_count >= 2
	return false


func _update_display() -> void:
	var phase1_complete = _is_phase1_complete()

	# Update Phase 1 labels
	var active_found = false
	for i in range(PHASE1_TASKS.size()):
		var task = PHASE1_TASKS[i]
		var label = _phase1_labels[i]
		var is_done = completed_tasks.get(task["id"], false)

		if is_done:
			label.text = "[OK] %s" % task["description"]
			label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3, 0.8))
		elif not active_found:
			label.text = ">> %s" % task["description"]
			label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5, 1.0))
			active_found = true
		else:
			label.text = "   %s" % task["description"]
			label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))

	# Update path headers and tasks
	for path_idx in range(PATHS.size()):
		var path = PATHS[path_idx]
		var path_color = Color(path["color"])
		var dimmed_color = Color(path_color, 0.3)

		# Header
		if phase1_complete:
			_path_header_labels[path_idx].add_theme_color_override("font_color", path_color)
		else:
			_path_header_labels[path_idx].add_theme_color_override("font_color", dimmed_color)

		# Tasks
		for task_idx in range(path["tasks"].size()):
			if task_idx >= _path_task_labels[path_idx].size():
				break
			var task = path["tasks"][task_idx]
			var label = _path_task_labels[path_idx][task_idx]
			var is_done = completed_tasks.get(task["id"], false)

			if is_done:
				label.text = "[OK] %s" % task["short"]
				label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3, 0.8))
			elif phase1_complete:
				label.text = "[ ] %s" % task["short"]
				label.add_theme_color_override("font_color", path_color)
			else:
				label.text = "[ ] %s" % task["short"]
				label.add_theme_color_override("font_color", dimmed_color)


func advance_day() -> void:
	_day_count += 1
	print("[TaskMenu] Day %d started" % _day_count)


func get_progress_data() -> Dictionary:
	return {
		"completed_tasks": completed_tasks.duplicate(),
		"day_count": _day_count,
	}


func load_progress_data(data: Dictionary) -> void:
	if data.has("completed_tasks"):
		completed_tasks = data["completed_tasks"].duplicate()
	if data.has("day_count"):
		_day_count = data["day_count"]
	_update_display()
