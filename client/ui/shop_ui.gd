extends Control

## ShopUI - Interface for Shnarken shop
## Buy items, sell items, and upgrade armor
## Triggered when player interacts with Shnarken NPC

const ItemData = preload("res://shared/item_data.gd")
const ArmorData = preload("res://shared/armor_data.gd")
const WeaponData = preload("res://shared/weapon_data.gd")
const Equipment = preload("res://shared/equipment.gd")

signal closed()

enum Tab { BUY, SELL, UPGRADE }

var current_tab: Tab = Tab.BUY
var player_inventory: Node = null
var player: Node = null
var current_shnarken: Node = null
var is_open: bool = false

# Buy-only items (no crafting recipe - must be purchased)
var shop_items: Array = [
	{"item_id": "tank_helmet", "price": 100},
	{"item_id": "tank_chest", "price": 200},
	{"item_id": "tank_pants", "price": 150},
	{"item_id": "tank_cape", "price": 120},
	{"item_id": "ice_wand", "price": 80},
	{"item_id": "glowing_medallion", "price": 50},  # Triggers Cyclops boss!
]

# Sell prices (50% of buy price for tank items, base prices for other items)
var sell_prices: Dictionary = {
	"wood": 1,
	"stone": 2,
	"iron": 5,
	"copper": 4,
	"resin": 2,
	"raw_venison": 3,
	"raw_pork": 3,
	"raw_mutton": 3,
	"cooked_venison": 8,
	"cooked_pork": 8,
	"cooked_mutton": 8,
	"pig_leather": 10,
	"deer_leather": 12,
	"pig_helmet": 25,
	"pig_chest": 50,
	"pig_pants": 40,
	"pig_cape": 30,
	"deer_helmet": 30,
	"deer_chest": 60,
	"deer_pants": 45,
	"deer_cape": 35,
}

# Upgrade costs (per level, 5% armor increase per level, max 3 levels)
const UPGRADE_BASE_COST: int = 50
const UPGRADE_MULTIPLIER: float = 1.5  # Each level costs 1.5x more

# UI nodes
var panel: Panel
var tab_container: HBoxContainer
var buy_tab_btn: Button
var sell_tab_btn: Button
var upgrade_tab_btn: Button
var content_container: VBoxContainer
var gold_label: Label
var dialogue_label: RichTextLabel

func _ready() -> void:
	_create_ui()
	visible = false  # Start hidden
	is_open = false

func _create_ui() -> void:
	# Main panel
	panel = Panel.new()
	panel.name = "ShopPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -250
	panel.offset_right = 300
	panel.offset_bottom = 250
	add_child(panel)

	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.08, 0.98)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	panel.add_child(bg)

	# Title
	var title = Label.new()
	title.text = "SHNARKEN'S BOOT EMPORIUM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 10
	title.offset_bottom = 40
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	panel.add_child(title)

	# Gold display
	gold_label = Label.new()
	gold_label.text = "Gold: 0"
	gold_label.anchor_left = 1.0
	gold_label.anchor_right = 1.0
	gold_label.offset_left = -120
	gold_label.offset_right = -10
	gold_label.offset_top = 10
	gold_label.offset_bottom = 40
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	panel.add_child(gold_label)

	# Dialogue area (Shnarken's snarky comments)
	dialogue_label = RichTextLabel.new()
	dialogue_label.bbcode_enabled = true
	dialogue_label.anchor_right = 1.0
	dialogue_label.offset_left = 15
	dialogue_label.offset_right = -15
	dialogue_label.offset_top = 45
	dialogue_label.offset_bottom = 95
	dialogue_label.add_theme_font_size_override("normal_font_size", 14)
	dialogue_label.text = "[i][color=lime]\"Welcome, welcome! Let me see what pitiful offerings you have...\"[/color][/i]"
	panel.add_child(dialogue_label)

	# Tab buttons
	tab_container = HBoxContainer.new()
	tab_container.anchor_right = 1.0
	tab_container.offset_left = 15
	tab_container.offset_right = -15
	tab_container.offset_top = 100
	tab_container.offset_bottom = 135
	panel.add_child(tab_container)

	buy_tab_btn = Button.new()
	buy_tab_btn.text = "BUY"
	buy_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_tab_btn.pressed.connect(_on_buy_tab)
	tab_container.add_child(buy_tab_btn)

	sell_tab_btn = Button.new()
	sell_tab_btn.text = "SELL"
	sell_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_tab_btn.pressed.connect(_on_sell_tab)
	tab_container.add_child(sell_tab_btn)

	upgrade_tab_btn = Button.new()
	upgrade_tab_btn.text = "UPGRADE"
	upgrade_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_tab_btn.pressed.connect(_on_upgrade_tab)
	tab_container.add_child(upgrade_tab_btn)

	# Content area (scrollable)
	var scroll = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 15
	scroll.offset_right = -15
	scroll.offset_top = 145
	scroll.offset_bottom = -50
	panel.add_child(scroll)

	content_container = VBoxContainer.new()
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("separation", 5)
	scroll.add_child(content_container)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.anchor_top = 1.0
	close_btn.anchor_bottom = 1.0
	close_btn.anchor_left = 0.5
	close_btn.anchor_right = 0.5
	close_btn.offset_left = -60
	close_btn.offset_right = 60
	close_btn.offset_top = -40
	close_btn.offset_bottom = -10
	close_btn.pressed.connect(hide_ui)
	panel.add_child(close_btn)

func _process(_delta: float) -> void:
	if not is_open:
		return

	# Close with ESC or Tab
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("toggle_inventory"):
		hide_ui()

## Show shop UI for a specific Shnarken
func show_ui(shnarken: Node) -> void:
	if is_open:
		return

	current_shnarken = shnarken
	is_open = true
	visible = true

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Get player reference
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p.get("is_local_player"):
			player = p
			player_inventory = p.get_node_or_null("Inventory")
			break

	# Show greeting dialogue
	if current_shnarken and current_shnarken.has_method("get_greeting_dialogue") and player:
		var greeting = current_shnarken.get_greeting_dialogue(player)
		dialogue_label.text = "[i][color=lime]\"%s\"[/color][/i]" % greeting
		if current_shnarken.has_method("start_talking"):
			current_shnarken.start_talking()

	# Default to buy tab
	_on_buy_tab()
	_update_gold_display()

	print("[ShopUI] Opened shop")

## Hide shop UI
func hide_ui() -> void:
	if not is_open:
		return

	is_open = false
	visible = false

	if current_shnarken and current_shnarken.has_method("stop_talking"):
		current_shnarken.stop_talking()

	current_shnarken = null

	# Recapture mouse for FPS controls
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	closed.emit()
	print("[ShopUI] Closed shop")

func _update_gold_display() -> void:
	if player:
		var gold = player.get("gold")
		if gold != null:
			gold_label.text = "Gold: %d" % gold
		else:
			gold_label.text = "Gold: 0"

func _on_buy_tab() -> void:
	current_tab = Tab.BUY
	_update_tab_buttons()
	_populate_buy_items()

func _on_sell_tab() -> void:
	current_tab = Tab.SELL
	_update_tab_buttons()
	_populate_sell_items()

func _on_upgrade_tab() -> void:
	current_tab = Tab.UPGRADE
	_update_tab_buttons()
	_populate_upgrade_items()

func _update_tab_buttons() -> void:
	buy_tab_btn.modulate = Color.WHITE if current_tab == Tab.BUY else Color(0.6, 0.6, 0.6)
	sell_tab_btn.modulate = Color.WHITE if current_tab == Tab.SELL else Color(0.6, 0.6, 0.6)
	upgrade_tab_btn.modulate = Color.WHITE if current_tab == Tab.UPGRADE else Color(0.6, 0.6, 0.6)

func _clear_content() -> void:
	for child in content_container.get_children():
		child.queue_free()

func _populate_buy_items() -> void:
	_clear_content()

	var player_gold = player.get("gold") if player else 0

	for shop_item in shop_items:
		var item_id = shop_item["item_id"]
		var price = shop_item["price"]
		var item_data = ItemDatabase.get_item(item_id)
		if not item_data:
			continue

		var row = _create_item_row(item_data.display_name, price, player_gold >= price)
		row.get_node("BuyBtn").pressed.connect(_on_buy_item.bind(item_id, price))
		content_container.add_child(row)

func _populate_sell_items() -> void:
	_clear_content()

	if not player_inventory:
		return

	var inventory_data = player_inventory.get_inventory_data()

	for i in inventory_data.size():
		var slot_data = inventory_data[i]
		if slot_data.is_empty():
			continue

		var item_id = slot_data.get("item", "")
		var amount = slot_data.get("amount", 0)
		if item_id.is_empty() or amount <= 0:
			continue

		# Skip equipped items
		if player and player.has_node("Equipment"):
			var equipment = player.get_node("Equipment")
			var is_equipped = false
			for slot in Equipment.EquipmentSlot.values():
				if equipment.get_equipped_item(slot) == item_id:
					is_equipped = true
					break
			if is_equipped:
				continue

		var sell_price = sell_prices.get(item_id, 1)
		var item_data = ItemDatabase.get_item(item_id)
		var display_name = item_data.display_name if item_data else item_id

		var row = _create_sell_row(display_name, amount, sell_price, i)
		content_container.add_child(row)

func _populate_upgrade_items() -> void:
	_clear_content()

	if not player or not player.has_node("Equipment"):
		var label = Label.new()
		label.text = "No equipment to upgrade!"
		content_container.add_child(label)
		return

	var equipment = player.get_node("Equipment")
	var has_upgradeable = false

	for slot in [Equipment.EquipmentSlot.HEAD, Equipment.EquipmentSlot.CHEST,
				 Equipment.EquipmentSlot.LEGS, Equipment.EquipmentSlot.CAPE]:
		var item_id = equipment.get_equipped_item(slot)
		if item_id.is_empty():
			continue

		var item_data = ItemDatabase.get_item(item_id)
		if not item_data or not item_data is ArmorData:
			continue

		has_upgradeable = true

		# Get current upgrade level (stored in player metadata or use 0)
		var upgrade_key = "upgrade_level_%s" % item_id
		var current_level = player.get_meta(upgrade_key, 0) if player.has_meta(upgrade_key) else 0
		var max_level = 3

		if current_level >= max_level:
			# Already maxed
			var row = _create_maxed_row(item_data.display_name, current_level)
			content_container.add_child(row)
		else:
			# Can upgrade
			var next_level = current_level + 1
			var cost = int(UPGRADE_BASE_COST * pow(UPGRADE_MULTIPLIER, current_level))
			var player_gold = player.get("gold") if player else 0

			var row = _create_upgrade_row(item_data.display_name, current_level, next_level, cost, player_gold >= cost, slot)
			content_container.add_child(row)

	if not has_upgradeable:
		var label = Label.new()
		label.text = "Equip some armor first, tadpole!"
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		content_container.add_child(label)

func _create_item_row(name: String, price: int, can_afford: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label = Label.new()
	name_label.text = name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.modulate = Color.WHITE if can_afford else Color(0.5, 0.5, 0.5)
	row.add_child(name_label)

	var price_label = Label.new()
	price_label.text = "%d gold" % price
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	row.add_child(price_label)

	var buy_btn = Button.new()
	buy_btn.name = "BuyBtn"
	buy_btn.text = "BUY"
	buy_btn.disabled = not can_afford
	buy_btn.custom_minimum_size = Vector2(60, 30)
	row.add_child(buy_btn)

	return row

func _create_sell_row(name: String, amount: int, price: int, slot_index: int) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label = Label.new()
	name_label.text = "%s x%d" % [name, amount]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var price_label = Label.new()
	price_label.text = "%d gold ea" % price
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	row.add_child(price_label)

	var sell_btn = Button.new()
	sell_btn.text = "SELL 1"
	sell_btn.custom_minimum_size = Vector2(70, 30)
	sell_btn.pressed.connect(_on_sell_item.bind(slot_index, 1, price))
	row.add_child(sell_btn)

	if amount > 1:
		var sell_all_btn = Button.new()
		sell_all_btn.text = "SELL ALL"
		sell_all_btn.custom_minimum_size = Vector2(80, 30)
		sell_all_btn.pressed.connect(_on_sell_item.bind(slot_index, amount, price * amount))
		row.add_child(sell_all_btn)

	return row

func _create_upgrade_row(name: String, current_level: int, next_level: int, cost: int, can_afford: bool, slot: int) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label = Label.new()
	name_label.text = "%s [Lv.%d → Lv.%d]" % [name, current_level, next_level]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.modulate = Color.WHITE if can_afford else Color(0.5, 0.5, 0.5)
	row.add_child(name_label)

	var bonus_label = Label.new()
	bonus_label.text = "+5% armor"
	bonus_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	row.add_child(bonus_label)

	var price_label = Label.new()
	price_label.text = "%d gold" % cost
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	row.add_child(price_label)

	var upgrade_btn = Button.new()
	upgrade_btn.text = "UPGRADE"
	upgrade_btn.disabled = not can_afford
	upgrade_btn.custom_minimum_size = Vector2(80, 30)
	upgrade_btn.pressed.connect(_on_upgrade_item.bind(slot, cost))
	row.add_child(upgrade_btn)

	return row

func _create_maxed_row(name: String, level: int) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label = Label.new()
	name_label.text = "%s [Lv.%d] - MAX" % [name, level]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	row.add_child(name_label)

	var maxed_label = Label.new()
	maxed_label.text = "FULLY UPGRADED"
	maxed_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	row.add_child(maxed_label)

	return row

# =============================================================================
# SHOP ACTIONS
# =============================================================================

func _on_buy_item(item_id: String, price: int) -> void:
	if not player:
		return

	var player_gold = player.get("gold")
	if player_gold == null or player_gold < price:
		dialogue_label.text = "[i][color=red]\"You don't have enough gold, you penniless tadpole!\"[/color][/i]"
		return

	# Request buy from server
	print("[ShopUI] Requesting to buy %s for %d gold" % [item_id, price])

	# Use direct call in singleplayer, RPC in multiplayer
	if not NetworkManager.call_server_method("handle_shop_buy", [item_id, price]):
		NetworkManager.rpc_request_shop_buy.rpc_id(1, item_id, price)

	# Special handling for boss summon items
	if item_id == "glowing_medallion":
		dialogue_label.text = "[i][color=red]\"Hehehehe... you FOOL! You've doomed yourself!\"[/color][/i]"
		# Close shop after brief delay, boss spawns via server
		await get_tree().create_timer(1.5).timeout
		hide_ui()
		return

	# Optimistically update UI (server will correct if wrong)
	dialogue_label.text = "[i][color=lime]\"Ah yes, excellent choice! That'll be %d gold.\"[/color][/i]" % price

	# Refresh after a short delay to allow server to process
	await get_tree().create_timer(0.2).timeout
	_update_gold_display()
	_on_buy_tab()

func _on_sell_item(slot_index: int, amount: int, total_price: int) -> void:
	if not player or not player_inventory:
		return

	# Request sell from server
	print("[ShopUI] Requesting to sell %d items from slot %d for %d gold" % [amount, slot_index, total_price])

	# Use direct call in singleplayer, RPC in multiplayer
	if not NetworkManager.call_server_method("handle_shop_sell", [slot_index, amount, total_price]):
		NetworkManager.rpc_request_shop_sell.rpc_id(1, slot_index, amount, total_price)

	# Snarky sell dialogue
	var snark_lines = [
		"I suppose I can take this off your hands... for a pittance.",
		"Hmph. I've seen better, but gold is gold.",
		"You call this quality? Fine, I'll buy it.",
		"My grandmother could craft better than this. Here's your gold.",
	]
	dialogue_label.text = "[i][color=lime]\"%s\"[/color][/i]" % snark_lines[randi() % snark_lines.size()]

	# Refresh after a short delay
	await get_tree().create_timer(0.2).timeout
	_update_gold_display()
	_on_sell_tab()

func _on_upgrade_item(slot: int, cost: int) -> void:
	if not player:
		return

	var player_gold = player.get("gold")
	if player_gold == null or player_gold < cost:
		dialogue_label.text = "[i][color=red]\"Can't afford my expertise? Come back with more gold!\"[/color][/i]"
		return

	# Request upgrade from server
	print("[ShopUI] Requesting to upgrade armor in slot %d for %d gold" % [slot, cost])

	# Use direct call in singleplayer, RPC in multiplayer
	if not NetworkManager.call_server_method("handle_shop_upgrade", [slot, cost]):
		NetworkManager.rpc_request_shop_upgrade.rpc_id(1, slot, cost)

	# Upgrade dialogue
	dialogue_label.text = "[i][color=lime]\"There... I've enhanced your armor. Try not to get it ruined immediately.\"[/color][/i]"

	# Refresh after a short delay
	await get_tree().create_timer(0.2).timeout
	_update_gold_display()
	_on_upgrade_tab()

## Check if shop is open
func is_shop_open() -> bool:
	return is_open
