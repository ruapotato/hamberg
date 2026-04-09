extends Control

## TaskMenu - Visual Skill Tree Web
## Enshrouded-style interconnected node web with icons.
## Center hub branches into 4 paths: Warrior, Ranger, Mage, Survival.
## Accessed via Pause Menu → Journal button.

# Phase 1 tasks (linear, center hub)
const PHASE1_TASKS: Array[Dictionary] = [
	{"id": "collect_wood", "description": "Collect wood", "short": "Collect wood", "icon": "wood"},
	{"id": "collect_stone", "description": "Collect stone", "short": "Collect stone", "icon": "stone"},
	{"id": "craft_hammer", "description": "Craft a Hammer", "short": "Craft Hammer", "icon": "hammer"},
	{"id": "place_workbench", "description": "Place a Workbench", "short": "Place Workbench", "icon": "workbench"},
	{"id": "craft_stone_axe", "description": "Craft a Stone Axe", "short": "Craft Stone Axe", "icon": "stone_axe"},
	{"id": "chop_tree", "description": "Chop a tree", "short": "Chop tree", "icon": "wood"},
]

# 4 branching paths
const PATHS: Array[Dictionary] = [
	{
		"name": "WARRIOR", "color": "ff8800", "angle": -PI/2,  # Up
		"tasks": [
			{"id": "craft_stone_sword", "short": "Stone Sword", "hint": "10 wood, 5 stone", "icon": "stone_sword"},
			{"id": "craft_tower_shield", "short": "Tower Shield", "hint": "15 wood", "icon": "tower_shield"},
			{"id": "craft_iron_sword", "short": "Iron Sword", "hint": "3 iron, 2 wood", "icon": "iron_sword"},
			{"id": "craft_bone_armor_full", "short": "Bone Armor Set", "hint": "Bone from zombies", "icon": "bone_armor_chest"},
		]
	},
	{
		"name": "RANGER", "color": "00ff6c", "angle": 0,  # Right
		"tasks": [
			{"id": "craft_stone_knife", "short": "Stone Knife", "hint": "5 wood, 2 stone", "icon": "stone_knife"},
			{"id": "craft_bow", "short": "Bow", "hint": "8 wood, 3 rope", "icon": "bow"},
			{"id": "craft_arrows", "short": "Arrows", "hint": "2 wood, 1 stone", "icon": "arrows"},
			{"id": "craft_iron_pickaxe", "short": "Iron Pickaxe", "hint": "3 iron, 2 wood", "icon": "iron_pickaxe"},
		]
	},
	{
		"name": "MAGE", "color": "ff0093", "angle": PI/2,  # Down
		"tasks": [
			{"id": "craft_arcane_wand", "short": "Arcane Wand", "hint": "Homing. Glowing Spores", "icon": "arcane_wand"},
			{"id": "craft_fire_wand", "short": "Fire Wand", "hint": "Fireball. Ember Core", "icon": "fire_wand"},
			{"id": "buy_ice_wand", "short": "Ice Wand", "hint": "Buy from Shnarken 80g", "icon": "ice_wand"},
			{"id": "craft_any_tier2_wand", "short": "Tier 2 Wand", "hint": "Lightning/Nature/Dark/Holy", "icon": "lightning_wand"},
		]
	},
	{
		"name": "SURVIVAL", "color": "ffeb00", "angle": PI,  # Left
		"tasks": [
			{"id": "build_shelter", "short": "Build Shelter", "hint": "Walls + roof", "icon": "wooden_wall"},
			{"id": "build_fireplace", "short": "Build Fireplace", "hint": "Cook food here", "icon": "stone"},
			{"id": "cook_meat", "short": "Cook Meat", "hint": "Kill a pig/deer/sheep", "icon": "cooked_venison"},
			{"id": "survive_first_night", "short": "Survive Night", "hint": "Zombies raid at night!", "icon": "torch"},
		]
	},
]

# Node layout
const NODE_RADIUS: float = 28.0
const HUB_RADIUS: float = 36.0
const BRANCH_SPACING: float = 80.0  # Distance between nodes along a branch
const BRANCH_START: float = 100.0   # Distance from center to first branch node
const ICON_SIZE: float = 36.0

# Tracking
var completed_tasks: Dictionary = {}
var player_ref: Node3D = null
var _hint_label: Label = null
var _is_visible: bool = false
var _day_count: int = 1
var _hovered_node: Dictionary = {}  # Currently hovered node info
var _tooltip_label: Label = null

# Cached icon textures
var _icon_cache: Dictionary = {}

# Node positions (calculated once)
var _hub_pos: Vector2 = Vector2.ZERO
var _phase1_positions: Array[Vector2] = []
var _path_positions: Array[Array] = []  # Array of Array[Vector2]
var _panel_rect: Rect2 = Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_to_group("task_menu")

	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Hint label at top-center (always visible)
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchors_preset = PRESET_TOP_WIDE
	_hint_label.offset_top = 8.0
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4, 0.8))
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)

	# Tooltip label (shown on hover)
	_tooltip_label = Label.new()
	_tooltip_label.visible = false
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_tooltip_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip_label)

	_is_visible = false
	_update_hint()

func _draw() -> void:
	if not _is_visible:
		return

	var center: Vector2 = size / 2.0
	_hub_pos = center

	# Dark overlay
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.05, 0.85))

	# Title
	var title_pos: Vector2 = Vector2(center.x - 60, 30)
	draw_string(ThemeDB.fallback_font, title_pos, "JOURNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.92, 0.0))

	var phase1_done: bool = _is_phase1_complete()

	# Draw Phase 1 as a ring around the hub
	_phase1_positions.clear()
	var p1_radius: float = 55.0
	for i in PHASE1_TASKS.size():
		var angle: float = -PI/2 + (float(i) / PHASE1_TASKS.size()) * TAU
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * p1_radius
		_phase1_positions.append(pos)

	# Draw connections for Phase 1 (ring)
	for i in PHASE1_TASKS.size():
		var next_i: int = (i + 1) % PHASE1_TASKS.size()
		var from_done: bool = completed_tasks.get(PHASE1_TASKS[i]["id"], false)
		var to_done: bool = completed_tasks.get(PHASE1_TASKS[next_i]["id"], false)
		var line_color: Color = Color(0.3, 0.9, 0.3, 0.6) if (from_done and to_done) else Color(0.3, 0.3, 0.4, 0.4)
		draw_line(_phase1_positions[i], _phase1_positions[next_i], line_color, 2.0, true)

	# Draw Phase 1 nodes
	for i in PHASE1_TASKS.size():
		var task: Dictionary = PHASE1_TASKS[i]
		var pos: Vector2 = _phase1_positions[i]
		var is_done: bool = completed_tasks.get(task["id"], false)
		_draw_node(pos, NODE_RADIUS * 0.7, is_done, Color(0.5, 0.7, 1.0), task.get("icon", ""), task["short"], not is_done and (i == 0 or completed_tasks.get(PHASE1_TASKS[i-1]["id"], false)))

	# Draw hub center
	var hub_color: Color = Color(1.0, 0.92, 0.0) if phase1_done else Color(0.3, 0.3, 0.4)
	draw_circle(center, HUB_RADIUS, Color(hub_color, 0.15))
	draw_arc(center, HUB_RADIUS, 0, TAU, 48, hub_color, 2.5, true)
	var hub_text: String = "BASICS" if not phase1_done else "PATHS"
	var hub_text_pos: Vector2 = center - Vector2(20, -5)
	draw_string(ThemeDB.fallback_font, hub_text_pos, hub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hub_color)

	# Draw Path branches
	_path_positions.clear()
	for path_idx in PATHS.size():
		var path: Dictionary = PATHS[path_idx]
		var path_color: Color = Color(path["color"])
		var angle: float = path["angle"]
		var direction: Vector2 = Vector2(cos(angle), sin(angle))

		var positions: Array[Vector2] = []

		# Connection from hub to first node
		var first_pos: Vector2 = center + direction * BRANCH_START
		var hub_edge: Vector2 = center + direction * HUB_RADIUS
		var line_alpha: float = 0.6 if phase1_done else 0.15
		draw_line(hub_edge, first_pos, Color(path_color, line_alpha), 2.0, true)

		# Draw path label
		var label_pos: Vector2 = center + direction * (BRANCH_START - 30)
		var label_offset: Vector2 = Vector2(-25, 4)
		draw_string(ThemeDB.fallback_font, label_pos + label_offset, path["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(path_color, 0.7 if phase1_done else 0.25))

		# Draw nodes along the branch
		for task_idx in path["tasks"].size():
			var task: Dictionary = path["tasks"][task_idx]
			var pos: Vector2 = center + direction * (BRANCH_START + task_idx * BRANCH_SPACING)
			positions.append(pos)

			# Connection to next node
			if task_idx < path["tasks"].size() - 1:
				var next_pos: Vector2 = center + direction * (BRANCH_START + (task_idx + 1) * BRANCH_SPACING)
				var this_done: bool = completed_tasks.get(task["id"], false)
				var next_done: bool = completed_tasks.get(path["tasks"][task_idx + 1]["id"], false)
				var conn_color: Color = Color(path_color, 0.6) if (this_done and next_done) else Color(path_color, 0.2 if phase1_done else 0.08)
				draw_line(pos, next_pos, conn_color, 2.0, true)

			var is_done: bool = completed_tasks.get(task["id"], false)
			var is_available: bool = phase1_done and (task_idx == 0 or completed_tasks.get(path["tasks"][task_idx - 1]["id"], false))
			_draw_node(pos, NODE_RADIUS, is_done, path_color, task.get("icon", ""), task["short"], is_available and not is_done)

		_path_positions.append(positions)

func _draw_node(pos: Vector2, radius: float, is_done: bool, color: Color, icon_id: String, label: String, is_active: bool) -> void:
	# Background circle
	if is_done:
		draw_circle(pos, radius, Color(color, 0.25))
		draw_arc(pos, radius, 0, TAU, 32, Color(0.3, 0.9, 0.3), 2.5, true)
	elif is_active:
		draw_circle(pos, radius, Color(color, 0.15))
		draw_arc(pos, radius, 0, TAU, 32, color, 2.0, true)
		# Pulse glow for active
		var pulse: float = (sin(Time.get_ticks_msec() / 500.0) + 1.0) * 0.5
		draw_arc(pos, radius + 3, 0, TAU, 32, Color(color, 0.2 + pulse * 0.3), 1.5, true)
	else:
		draw_circle(pos, radius, Color(0.1, 0.1, 0.15, 0.5))
		draw_arc(pos, radius, 0, TAU, 32, Color(0.3, 0.3, 0.4, 0.3), 1.5, true)

	# Icon
	var tex: Texture2D = _get_icon(icon_id)
	if tex:
		var icon_rect: Rect2 = Rect2(pos - Vector2(ICON_SIZE/2, ICON_SIZE/2), Vector2(ICON_SIZE, ICON_SIZE))
		var alpha: float = 1.0 if (is_done or is_active) else 0.25
		draw_texture_rect(tex, icon_rect, false, Color(1, 1, 1, alpha))

	# Checkmark for completed
	if is_done:
		draw_string(ThemeDB.fallback_font, pos + Vector2(radius * 0.4, -radius * 0.3), "OK", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 1.0, 0.3))

	# Label below node
	var text_width: float = label.length() * 6.0
	var text_pos: Vector2 = pos + Vector2(-text_width/2, radius + 14)
	var text_color: Color = Color(1, 1, 1, 0.9) if (is_done or is_active) else Color(0.5, 0.5, 0.5, 0.4)
	draw_string(ThemeDB.fallback_font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)

func _get_icon(icon_id: String) -> Texture2D:
	if _icon_cache.has(icon_id):
		return _icon_cache[icon_id]
	var path: String = "res://images/icons/%s.png" % icon_id
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_icon_cache[icon_id] = tex
		return tex
	_icon_cache[icon_id] = null
	return null

func _process(_delta: float) -> void:
	if _is_visible:
		queue_redraw()  # Redraw for pulse animation

	# Handle tooltip on mouse hover
	if _is_visible and _tooltip_label:
		var mouse: Vector2 = get_local_mouse_position()
		var found_hover: bool = false

		# Check path nodes
		for path_idx in _path_positions.size():
			if path_idx >= PATHS.size():
				break
			for task_idx in _path_positions[path_idx].size():
				var pos: Vector2 = _path_positions[path_idx][task_idx]
				if mouse.distance_to(pos) < NODE_RADIUS:
					var task: Dictionary = PATHS[path_idx]["tasks"][task_idx]
					var hint: String = task.get("hint", "")
					var is_done: bool = completed_tasks.get(task["id"], false)
					_tooltip_label.text = "%s%s" % [task["short"], ("\n" + hint if hint else "") + ("\n[Completed]" if is_done else "")]
					_tooltip_label.position = mouse + Vector2(15, -10)
					_tooltip_label.visible = true
					found_hover = true
					break
			if found_hover:
				break

		# Check phase 1 nodes
		if not found_hover:
			for i in _phase1_positions.size():
				if i >= PHASE1_TASKS.size():
					break
				if mouse.distance_to(_phase1_positions[i]) < NODE_RADIUS * 0.7:
					var task: Dictionary = PHASE1_TASKS[i]
					var is_done: bool = completed_tasks.get(task["id"], false)
					_tooltip_label.text = "%s%s" % [task["short"], "\n[Completed]" if is_done else ""]
					_tooltip_label.position = mouse + Vector2(15, -10)
					_tooltip_label.visible = true
					found_hover = true
					break

		if not found_hover:
			_tooltip_label.visible = false

func _unhandled_input(_event: InputEvent) -> void:
	pass  # Journal accessed via pause menu

func toggle_full_view() -> void:
	_is_visible = not _is_visible
	if _is_visible:
		queue_redraw()
	else:
		if _tooltip_label:
			_tooltip_label.visible = false

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

	var play_sounds: bool = player_ref.is_game_loaded if "is_game_loaded" in player_ref else true
	var inventory = player_ref.get_node_or_null("Inventory")

	for task in PHASE1_TASKS:
		var task_id: String = task["id"]
		if completed_tasks.get(task_id, false):
			continue
		if _check_task(task_id, inventory):
			completed_tasks[task_id] = true
			if play_sounds:
				SoundManager.play_ui_sound("quest_complete")

	if _is_phase1_complete() and not completed_tasks.get("_phase1_milestone", false):
		completed_tasks["_phase1_milestone"] = true
		if play_sounds:
			SoundManager.play_ui_sound("level_up")

	if _is_phase1_complete():
		for path in PATHS:
			for task in path["tasks"]:
				var task_id: String = task["id"]
				if completed_tasks.get(task_id, false):
					continue
				if _check_task(task_id, inventory):
					completed_tasks[task_id] = true
					if play_sounds:
						SoundManager.play_ui_sound("quest_complete")

	_update_hint()

func _check_task(task_id: String, inventory: Node) -> bool:
	match task_id:
		"collect_wood":
			return inventory and inventory.has_item("wood", 1)
		"collect_stone":
			return inventory and inventory.has_item("stone", 1)
		"craft_hammer":
			return inventory and inventory.has_item("hammer", 1)
		"place_workbench":
			return get_tree().get_nodes_in_group("workbenches").size() > 0
		"craft_stone_axe":
			return inventory and inventory.has_item("stone_axe", 1)
		"chop_tree":
			return inventory and inventory.has_item("wood", 8)
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
		"craft_bow":
			return inventory and inventory.has_item("bow", 1)
		"craft_arrows":
			return inventory and inventory.has_item("arrows", 1)
		"craft_stone_knife":
			return inventory and inventory.has_item("stone_knife", 1)
		"craft_iron_pickaxe":
			return inventory and inventory.has_item("iron_pickaxe", 1)
		"craft_arcane_wand":
			return inventory and inventory.has_item("arcane_wand", 1)
		"craft_fire_wand":
			return inventory and inventory.has_item("fire_wand", 1)
		"buy_ice_wand":
			return inventory and inventory.has_item("ice_wand", 1)
		"craft_any_tier2_wand":
			if not inventory:
				return false
			return inventory.has_item("lightning_wand", 1) or inventory.has_item("nature_wand", 1) or inventory.has_item("dark_wand", 1) or inventory.has_item("holy_wand", 1)
		"build_shelter":
			var has_wall: bool = false
			var has_roof: bool = false
			var world_node: Node = get_tree().root.get_node_or_null("Main/Client/World")
			if world_node:
				for child in world_node.get_children():
					var cname: String = child.name.to_lower()
					if "wall" in cname:
						has_wall = true
					if "roof" in cname:
						has_roof = true
			return has_wall and has_roof
		"build_fireplace":
			var world_node: Node = get_tree().root.get_node_or_null("Main/Client/World")
			if world_node:
				for child in world_node.get_children():
					if "fireplace" in child.name.to_lower() or "fire_pit" in child.name.to_lower() or "campfire" in child.name.to_lower() or "cooking" in child.name.to_lower():
						return true
			return false
		"cook_meat":
			if not inventory:
				return false
			return inventory.has_item("cooked_venison", 1) or inventory.has_item("cooked_pork", 1) or inventory.has_item("cooked_mutton", 1)
		"survive_first_night":
			return _day_count >= 2
	return false

func _update_hint() -> void:
	if not _hint_label:
		return
	for task in PHASE1_TASKS:
		if not completed_tasks.get(task["id"], false):
			_hint_label.text = ">> %s" % task["description"]
			return
	for path in PATHS:
		for task in path["tasks"]:
			if not completed_tasks.get(task["id"], false):
				var hint: String = task.get("hint", "")
				if hint:
					_hint_label.text = ">> %s: %s — %s" % [path["name"], task["short"], hint]
				else:
					_hint_label.text = ">> %s: %s" % [path["name"], task["short"]]
				return
	_hint_label.text = "All tasks complete!"

func advance_day() -> void:
	_day_count += 1

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
	_update_hint()
