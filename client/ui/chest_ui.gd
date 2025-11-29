extends Control

## ChestUI - Interface for interacting with storage chests
## Shows chest inventory on left, player inventory on right
## Supports drag-drop between inventories and quick-sort (hold E)

const InventorySlot = preload("res://client/ui/inventory_slot.tscn")
const CHEST_SLOTS: int = 20
const PLAYER_SLOTS: int = 30
const COLUMNS: int = 5

signal closed()

var chest_slots: Array[Node] = []
var player_slots: Array[Node] = []
var player_inventory: Node = null
var current_chest: Node = null  # Reference to the chest being accessed
var is_open: bool = false

# Controller navigation
var focused_slot: int = 0  # Current focused slot index
var in_player_grid: bool = false  # True if focus is in player grid, false for chest grid
var picked_up_slot: int = -1  # Slot being moved (-1 = none)
var picked_up_from_player: bool = false  # Was the picked up item from player grid?
const CHEST_COLUMNS: int = 5
const PLAYER_COLUMNS: int = 5

@onready var panel: Panel = $Panel
@onready var chest_grid: GridContainer = $Panel/HBoxContainer/ChestPanel/ChestGrid
@onready var player_grid: GridContainer = $Panel/HBoxContainer/PlayerPanel/PlayerGrid
@onready var chest_title: Label = $Panel/HBoxContainer/ChestPanel/Title
@onready var player_title: Label = $Panel/HBoxContainer/PlayerPanel/Title

func _ready() -> void:
	_create_slots()
	hide_ui()

func _create_slots() -> void:
	# Create chest slots
	chest_slots.clear()
	if chest_grid:
		chest_grid.columns = COLUMNS
		for i in CHEST_SLOTS:
			var slot = InventorySlot.instantiate()
			slot.slot_index = i
			slot.is_hotbar_slot = false
			slot.slot_clicked.connect(_on_chest_slot_clicked.bind(i))
			slot.drag_ended.connect(_on_chest_slot_drag_ended)
			slot.drag_dropped_outside.connect(_on_chest_slot_dropped_outside)
			chest_grid.add_child(slot)
			chest_slots.append(slot)

	# Create player slots
	player_slots.clear()
	if player_grid:
		player_grid.columns = COLUMNS
		for i in PLAYER_SLOTS:
			var slot = InventorySlot.instantiate()
			slot.slot_index = i
			slot.is_hotbar_slot = false
			slot.slot_clicked.connect(_on_player_slot_clicked.bind(i))
			slot.drag_ended.connect(_on_player_slot_drag_ended)
			slot.drag_dropped_outside.connect(_on_player_slot_dropped_outside)
			player_grid.add_child(slot)
			player_slots.append(slot)

func _process(_delta: float) -> void:
	if not is_open:
		return

	# Close with Tab (ESC is handled by client.gd to coordinate with pause menu)
	if Input.is_action_just_pressed("toggle_inventory"):
		hide_ui()
		return

	# Controller D-pad navigation
	# D-pad left/right navigates horizontally
	if Input.is_action_just_pressed("hotbar_next"):
		_move_focus(1, 0)  # Right
	elif Input.is_action_just_pressed("hotbar_prev"):
		_move_focus(-1, 0)  # Left

	# D-pad up/down navigates vertically
	if Input.is_action_just_pressed("hotbar_equip"):
		_move_focus(0, -1)  # Up
	elif Input.is_action_just_pressed("hotbar_unequip"):
		_move_focus(0, 1)  # Down

	# A button: Pick up/drop item (for moving items between grids)
	if Input.is_action_just_pressed("interact"):
		_handle_item_pickup_drop()

## Open chest UI with a specific chest
func show_ui(chest: Node, quick_sort: bool = false) -> void:
	if is_open:
		return

	current_chest = chest
	is_open = true
	visible = true

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	refresh_display()

	# Initialize controller navigation
	focused_slot = 0
	in_player_grid = false
	picked_up_slot = -1
	picked_up_from_player = false
	_update_focus_visual()

	# Quick-sort: auto-deposit matching items
	if quick_sort:
		_perform_quick_sort()

	print("[ChestUI] Opened chest")

## Hide chest UI
func hide_ui() -> void:
	if not is_open:
		return

	is_open = false
	visible = false
	current_chest = null

	# Recapture mouse for FPS controls
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	closed.emit()
	print("[ChestUI] Closed chest")

## Set player inventory reference
func set_player_inventory(inventory: Node) -> void:
	player_inventory = inventory
	refresh_display()

## Refresh all slot displays
func refresh_display() -> void:
	_refresh_chest_slots()
	_refresh_player_slots()

func _refresh_chest_slots() -> void:
	if not current_chest:
		for slot in chest_slots:
			slot.set_item_data({})
		return

	var chest_inventory = current_chest.get_inventory_data()
	for i in CHEST_SLOTS:
		if i < chest_inventory.size():
			var data = chest_inventory[i]
			# Convert chest format to inventory slot format
			var slot_data = {}
			if data.item_name != "" and data.quantity > 0:
				slot_data = {"item": data.item_name, "amount": data.quantity}
			chest_slots[i].set_item_data(slot_data)
		else:
			chest_slots[i].set_item_data({})

func _refresh_player_slots() -> void:
	if not player_inventory:
		for slot in player_slots:
			slot.set_item_data({})
		return

	var inventory_data = player_inventory.get_inventory_data()
	for i in PLAYER_SLOTS:
		if i < inventory_data.size():
			player_slots[i].set_item_data(inventory_data[i])
		else:
			player_slots[i].set_item_data({})

## Handle click on chest slot
func _on_chest_slot_clicked(slot_index: int) -> void:
	print("[ChestUI] Clicked chest slot %d" % slot_index)

## Handle click on player slot
func _on_player_slot_clicked(slot_index: int) -> void:
	print("[ChestUI] Clicked player slot %d" % slot_index)

## Handle drag within chest grid or from player to chest
func _on_chest_slot_drag_ended(from_slot: int, to_slot: int) -> void:
	print("[ChestUI] _on_chest_slot_drag_ended: from=%d, to=%d" % [from_slot, to_slot])
	# Check if target is in player grid
	var target_slot = _get_slot_under_mouse()
	if target_slot and target_slot in player_slots:
		# Dragged from chest to player
		var player_slot_index = player_slots.find(target_slot)
		_transfer_chest_to_player(from_slot, player_slot_index)
	else:
		# Dragged within chest
		_swap_chest_slots(from_slot, to_slot)

## Handle drag within player grid or from chest to player
func _on_player_slot_drag_ended(from_slot: int, to_slot: int) -> void:
	print("[ChestUI] _on_player_slot_drag_ended: from=%d, to=%d" % [from_slot, to_slot])
	# Check if target is in chest grid
	var target_slot = _get_slot_under_mouse()
	if target_slot and target_slot in chest_slots:
		# Dragged from player to chest
		var chest_slot_index = chest_slots.find(target_slot)
		_transfer_player_to_chest(from_slot, chest_slot_index)
	else:
		# Dragged within player inventory - use server RPC
		NetworkManager.rpc_request_swap_slots.rpc_id(1, from_slot, to_slot)

## Handle when chest slot reports dropped outside - check if it landed on player grid
func _on_chest_slot_dropped_outside(from_slot: int) -> void:
	var target_slot = _get_slot_under_mouse()
	print("[ChestUI] Chest slot %d dropped outside, target_slot=%s" % [from_slot, target_slot])
	if target_slot and target_slot in player_slots:
		# Dropped from chest onto player inventory
		var player_slot_index = player_slots.find(target_slot)
		print("[ChestUI] Target is player slot %d - transferring chest->player" % player_slot_index)
		_transfer_chest_to_player(from_slot, player_slot_index)
	else:
		print("[ChestUI] Target NOT in player_slots (target=%s, in_chest=%s)" % [target_slot, target_slot in chest_slots if target_slot else "N/A"])

## Handle when player slot reports dropped outside - check if it landed on chest grid
func _on_player_slot_dropped_outside(from_slot: int) -> void:
	var target_slot = _get_slot_under_mouse()
	print("[ChestUI] Player slot %d dropped outside, target_slot=%s" % [from_slot, target_slot])
	if target_slot and target_slot in chest_slots:
		# Dropped from player onto chest
		var chest_slot_index = chest_slots.find(target_slot)
		print("[ChestUI] Target is chest slot %d - transferring player->chest" % chest_slot_index)
		_transfer_player_to_chest(from_slot, chest_slot_index)
	else:
		print("[ChestUI] Target NOT in chest_slots (target=%s, in_player=%s)" % [target_slot, target_slot in player_slots if target_slot else "N/A"])

## Transfer item from chest to player inventory
func _transfer_chest_to_player(chest_slot: int, player_slot: int) -> void:
	if not current_chest or not player_inventory:
		return

	var chest_inventory = current_chest.get_inventory_data()
	if chest_slot >= chest_inventory.size():
		return

	var chest_data = chest_inventory[chest_slot]
	if chest_data.item_name.is_empty() or chest_data.quantity <= 0:
		return

	print("[ChestUI] Transfer from chest[%d] to player[%d]: %s x%d" % [chest_slot, player_slot, chest_data.item_name, chest_data.quantity])

	# Request transfer via server
	NetworkManager.rpc_request_chest_to_player.rpc_id(1, chest_slot, player_slot)

## Transfer item from player to chest
func _transfer_player_to_chest(player_slot: int, chest_slot: int) -> void:
	if not current_chest or not player_inventory:
		return

	var inventory_data = player_inventory.get_inventory_data()
	if player_slot >= inventory_data.size():
		return

	var player_data = inventory_data[player_slot]
	if player_data.is_empty():
		return

	var item_name = player_data.get("item", "")
	var amount = player_data.get("amount", 0)
	if item_name.is_empty() or amount <= 0:
		return

	print("[ChestUI] Transfer from player[%d] to chest[%d]: %s x%d" % [player_slot, chest_slot, item_name, amount])

	# Request transfer via server
	NetworkManager.rpc_request_player_to_chest.rpc_id(1, player_slot, chest_slot)

## Swap two slots within the chest
func _swap_chest_slots(from_slot: int, to_slot: int) -> void:
	if not current_chest:
		return

	# Request swap via server
	NetworkManager.rpc_request_chest_swap.rpc_id(1, from_slot, to_slot)

## Get any inventory slot under the mouse cursor
func _get_slot_under_mouse() -> Node:
	var mouse_pos = get_viewport().get_mouse_position()
	print("[ChestUI] _get_slot_under_mouse: mouse_pos=%s, chest_slots=%d, player_slots=%d" % [mouse_pos, chest_slots.size(), player_slots.size()])

	# Check chest slots
	for i in chest_slots.size():
		var slot = chest_slots[i]
		var rect = slot.get_global_rect()
		if rect.has_point(mouse_pos):
			print("[ChestUI] Found chest slot %d at rect %s" % [i, rect])
			return slot

	# Check player slots
	for i in player_slots.size():
		var slot = player_slots[i]
		var rect = slot.get_global_rect()
		if rect.has_point(mouse_pos):
			print("[ChestUI] Found player slot %d at rect %s" % [i, rect])
			return slot

	print("[ChestUI] No slot found under mouse")
	return null

## Quick-sort: auto-deposit items that match what's already in the chest
func _perform_quick_sort() -> void:
	if not current_chest or not player_inventory:
		return

	# Get list of item types already in chest
	var chest_item_types: Array[String] = []
	var chest_inventory = current_chest.get_inventory_data()
	for data in chest_inventory:
		if data.item_name != "" and data.quantity > 0:
			if not chest_item_types.has(data.item_name):
				chest_item_types.append(data.item_name)

	if chest_item_types.is_empty():
		print("[ChestUI] Quick-sort: Chest is empty, nothing to match")
		return

	# Find matching items in player inventory and transfer them
	var inventory_data = player_inventory.get_inventory_data()
	for i in inventory_data.size():
		var slot_data = inventory_data[i]
		if slot_data.is_empty():
			continue

		var item_name = slot_data.get("item", "")
		if item_name in chest_item_types:
			# Request to deposit this item to chest
			print("[ChestUI] Quick-sort: Depositing %s from slot %d" % [item_name, i])
			NetworkManager.rpc_request_quick_deposit.rpc_id(1, i)

	print("[ChestUI] Quick-sort complete")

## Check if UI is currently open
func is_ui_open() -> bool:
	return is_open

## Move focus in grid (for controller D-pad navigation)
## Chest is on the LEFT, Player inventory is on the RIGHT
## So horizontal navigation (left/right) switches between grids
func _move_focus(dx: int, dy: int) -> void:
	var columns = PLAYER_COLUMNS if in_player_grid else CHEST_COLUMNS
	var max_slots = PLAYER_SLOTS if in_player_grid else CHEST_SLOTS

	# Calculate current row and column
	var current_row = focused_slot / columns
	var current_col = focused_slot % columns

	# Calculate new position
	var new_row = current_row + dy
	var new_col = current_col + dx

	# Calculate max rows for current grid
	var max_rows = (max_slots + columns - 1) / columns

	# Handle HORIZONTAL navigation between grids (chest left, player right)
	if new_col < 0:
		# Going left
		if in_player_grid:
			# Switch to chest grid (go to rightmost column, same row if possible)
			in_player_grid = false
			var chest_max_rows = (CHEST_SLOTS + CHEST_COLUMNS - 1) / CHEST_COLUMNS
			new_row = clamp(current_row, 0, chest_max_rows - 1)
			new_col = CHEST_COLUMNS - 1  # Rightmost column of chest
			focused_slot = new_row * CHEST_COLUMNS + new_col
			focused_slot = clamp(focused_slot, 0, CHEST_SLOTS - 1)
			_update_focus_visual()
			return
		else:
			# Already at left edge of chest grid, clamp
			new_col = 0
	elif new_col >= columns:
		# Going right
		if not in_player_grid:
			# Switch to player grid (go to leftmost column, same row if possible)
			in_player_grid = true
			var player_max_rows = (PLAYER_SLOTS + PLAYER_COLUMNS - 1) / PLAYER_COLUMNS
			new_row = clamp(current_row, 0, player_max_rows - 1)
			new_col = 0  # Leftmost column of player
			focused_slot = new_row * PLAYER_COLUMNS + new_col
			focused_slot = clamp(focused_slot, 0, PLAYER_SLOTS - 1)
			_update_focus_visual()
			return
		else:
			# Already at right edge of player grid, clamp
			new_col = columns - 1

	# Handle vertical navigation (clamp to current grid bounds)
	new_row = clamp(new_row, 0, max_rows - 1)

	# Calculate new focused slot
	var new_focus = new_row * columns + new_col

	# Clamp to valid slot range
	new_focus = clamp(new_focus, 0, max_slots - 1)

	if new_focus != focused_slot:
		focused_slot = new_focus
		_update_focus_visual()

## Update visual highlight for focused slot
func _update_focus_visual() -> void:
	# Clear all highlights
	for i in chest_slots.size():
		if chest_slots[i].has_method("set_selected"):
			var is_highlighted = (not in_player_grid and i == focused_slot) or (picked_up_slot == i and not picked_up_from_player)
			chest_slots[i].set_selected(is_highlighted)

	for i in player_slots.size():
		if player_slots[i].has_method("set_selected"):
			var is_highlighted = (in_player_grid and i == focused_slot) or (picked_up_slot == i and picked_up_from_player)
			player_slots[i].set_selected(is_highlighted)

## Handle picking up and dropping items with A button
func _handle_item_pickup_drop() -> void:
	if picked_up_slot == -1:
		# No item picked up - try to pick up focused item
		if in_player_grid:
			if not player_inventory:
				return
			var inventory_data = player_inventory.get_inventory_data()
			if focused_slot >= inventory_data.size():
				return
			var slot_data = inventory_data[focused_slot]
			if slot_data.is_empty():
				return
			# Pick up from player grid
			picked_up_slot = focused_slot
			picked_up_from_player = true
			print("[ChestUI] Picked up item from player slot %d" % picked_up_slot)
		else:
			if not current_chest:
				return
			var chest_inventory = current_chest.get_inventory_data()
			if focused_slot >= chest_inventory.size():
				return
			var chest_data = chest_inventory[focused_slot]
			if chest_data.item_name.is_empty() or chest_data.quantity <= 0:
				return
			# Pick up from chest grid
			picked_up_slot = focused_slot
			picked_up_from_player = false
			print("[ChestUI] Picked up item from chest slot %d" % picked_up_slot)
		_update_focus_visual()
	else:
		# Item already picked up - drop it at focused slot
		if picked_up_slot == focused_slot and picked_up_from_player == in_player_grid:
			# Dropping on same slot in same grid - just cancel
			print("[ChestUI] Cancelled move")
			picked_up_slot = -1
			picked_up_from_player = false
			_update_focus_visual()
			return

		# Determine transfer type
		if picked_up_from_player and in_player_grid:
			# Swap within player inventory
			print("[ChestUI] Swapping player slots %d and %d" % [picked_up_slot, focused_slot])
			NetworkManager.rpc_request_swap_slots.rpc_id(1, picked_up_slot, focused_slot)
		elif not picked_up_from_player and not in_player_grid:
			# Swap within chest
			print("[ChestUI] Swapping chest slots %d and %d" % [picked_up_slot, focused_slot])
			NetworkManager.rpc_request_chest_swap.rpc_id(1, picked_up_slot, focused_slot)
		elif picked_up_from_player and not in_player_grid:
			# Transfer from player to chest
			print("[ChestUI] Transferring player[%d] to chest[%d]" % [picked_up_slot, focused_slot])
			_transfer_player_to_chest(picked_up_slot, focused_slot)
		else:
			# Transfer from chest to player
			print("[ChestUI] Transferring chest[%d] to player[%d]" % [picked_up_slot, focused_slot])
			_transfer_chest_to_player(picked_up_slot, focused_slot)

		picked_up_slot = -1
		picked_up_from_player = false
		_update_focus_visual()
