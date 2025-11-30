extends "res://shared/buildable/buildable_object.gd"

## CookingStation - A grill for cooking raw meat
## Place over a fireplace to cook food
## Press E to add raw meat or remove cooked/burned food

signal cooking_started(slot: int, item_name: String)
signal cooking_finished(slot: int, item_name: String, result: String)
signal item_burned(slot: int)

const COOKING_TIME: float = 17.0  # Seconds to cook meat
const BURN_TIME: float = 30.0     # Seconds total before meat burns (13 more after cooked)
const MAX_SLOTS: int = 2

enum CookState { EMPTY, RAW, COOKING, COOKED, BURNED }

# Cooking slot data
var cooking_slots: Array[Dictionary] = []
var is_over_fire: bool = false

# Visual representations of cooking items
var slot_visuals: Array[MeshInstance3D] = []

# Colors for different cooking states
const COLOR_RAW = Color(0.7, 0.2, 0.2)      # Red raw meat
const COLOR_COOKING = Color(0.6, 0.35, 0.2)  # Browning
const COLOR_COOKED = Color(0.45, 0.28, 0.15) # Nice brown cooked
const COLOR_BURNED = Color(0.1, 0.1, 0.1)    # Black charcoal

# Sound effects
var sizzle_player: AudioStreamPlayer3D
var complete_player: AudioStreamPlayer3D
var burn_player: AudioStreamPlayer3D
var sizzle_sound: AudioStream
var complete_sound: AudioStream
var burn_sound: AudioStream

# Cooking recipes: raw item -> cooked item
const COOKING_RECIPES: Dictionary = {
	"raw_venison": "cooked_venison",
	"raw_pork": "cooked_pork",
	"raw_mutton": "cooked_mutton",
}

func _ready() -> void:
	super._ready()
	add_to_group("cooking_station")
	add_to_group("interactable")

	# Initialize cooking slots
	for i in MAX_SLOTS:
		cooking_slots.append({
			"item": "",
			"progress": 0.0,
			"cooked_item": "",
			"state": CookState.EMPTY
		})

	# Create visual meshes for items being cooked
	_create_slot_visuals()

	# Setup audio players
	_setup_audio()

func _process(delta: float) -> void:
	# Track if anything is actively cooking for sizzle sound
	var is_cooking_active = false

	if not is_over_fire:
		_stop_sizzle()
		return

	# Process cooking for each slot
	for slot_idx in cooking_slots.size():
		var slot = cooking_slots[slot_idx]
		if slot.state == CookState.EMPTY:
			continue

		# Only progress if raw, cooking, or cooked (not already burned)
		if slot.state == CookState.BURNED:
			continue

		# Something is cooking
		is_cooking_active = true
		slot.progress += delta

		# Update state based on progress
		if slot.progress < COOKING_TIME:
			if slot.state != CookState.COOKING:
				slot.state = CookState.COOKING
		elif slot.progress < BURN_TIME:
			if slot.state != CookState.COOKED:
				slot.state = CookState.COOKED
				print("[CookingStation] Slot %d: %s is now cooked! -> %s" % [slot_idx, slot.item, slot.cooked_item])
				cooking_finished.emit(slot_idx, slot.item, slot.cooked_item)
				_play_complete_sound()
		else:
			if slot.state != CookState.BURNED:
				slot.state = CookState.BURNED
				slot.cooked_item = "charcoal"
				print("[CookingStation] Slot %d: Food burned to charcoal!" % slot_idx)
				item_burned.emit(slot_idx)
				_play_burn_sound()

		# Update visual
		_update_slot_visual(slot_idx)

	# Update sizzle sound
	if is_cooking_active:
		_start_sizzle()
	else:
		_stop_sizzle()

func _create_slot_visuals() -> void:
	var meat_mesh = CylinderMesh.new()
	meat_mesh.top_radius = 0.1
	meat_mesh.bottom_radius = 0.12
	meat_mesh.height = 0.06

	for i in MAX_SLOTS:
		var visual = MeshInstance3D.new()
		visual.mesh = meat_mesh.duplicate()

		var mat = StandardMaterial3D.new()
		mat.albedo_color = COLOR_RAW
		visual.set_surface_override_material(0, mat)
		visual.visible = false

		var slot_marker = get_node_or_null("CookingSlot%d" % (i + 1))
		if slot_marker:
			visual.position = slot_marker.position
		else:
			visual.position = Vector3(-0.2 + i * 0.4, 0.55, 0)

		add_child(visual)
		slot_visuals.append(visual)

func _setup_audio() -> void:
	# Load sound effects
	sizzle_sound = load("res://audio/generated/cooking_sizzle.wav")
	complete_sound = load("res://audio/generated/cooking_complete.wav")
	burn_sound = load("res://audio/generated/cooking_burn.wav")

	# Create sizzle player (looping)
	sizzle_player = AudioStreamPlayer3D.new()
	sizzle_player.stream = sizzle_sound
	sizzle_player.max_distance = 15.0
	sizzle_player.unit_size = 3.0
	sizzle_player.autoplay = false
	sizzle_player.finished.connect(_on_sizzle_finished)
	add_child(sizzle_player)

	# Create complete sound player
	complete_player = AudioStreamPlayer3D.new()
	complete_player.stream = complete_sound
	complete_player.max_distance = 20.0
	complete_player.unit_size = 4.0
	add_child(complete_player)

	# Create burn sound player
	burn_player = AudioStreamPlayer3D.new()
	burn_player.stream = burn_sound
	burn_player.max_distance = 20.0
	burn_player.unit_size = 4.0
	add_child(burn_player)

## Called when player presses E on this station (auto-select item)
func interact(player: Node) -> void:
	if not player:
		return

	var inventory = player.get_node_or_null("Inventory")
	if not inventory:
		return

	# First, check if any slot has cooked/burned food to take
	for slot_idx in cooking_slots.size():
		var slot = cooking_slots[slot_idx]
		if slot.state == CookState.COOKED or slot.state == CookState.BURNED:
			var result_item = remove_item(slot_idx)
			if not result_item.is_empty():
				inventory.add_item(result_item, 1)
				print("[CookingStation] Player took %s from slot %d" % [result_item, slot_idx])
				return

	# No cooked food - try to add raw meat from inventory
	for raw_item in COOKING_RECIPES.keys():
		if inventory.has_item(raw_item, 1):
			var slot_idx = add_item_to_cook(raw_item)
			if slot_idx >= 0:
				inventory.remove_item(raw_item, 1)
				print("[CookingStation] Player added %s to slot %d" % [raw_item, slot_idx])
				return

	print("[CookingStation] No raw meat in inventory to cook")

## Called when player presses a number key to cook a specific item
func interact_with_item(player: Node, item_name: String) -> bool:
	if not player:
		return false

	var inventory = player.get_node_or_null("Inventory")
	if not inventory:
		return false

	# Check if this item can be cooked
	if not COOKING_RECIPES.has(item_name):
		print("[CookingStation] %s cannot be cooked" % item_name)
		return false

	# Check if player has the item
	if not inventory.has_item(item_name, 1):
		print("[CookingStation] Player doesn't have %s" % item_name)
		return false

	# Try to add it to a cooking slot
	var slot_idx = add_item_to_cook(item_name)
	if slot_idx >= 0:
		inventory.remove_item(item_name, 1)
		print("[CookingStation] Player added %s to slot %d (manual)" % [item_name, slot_idx])
		return true

	print("[CookingStation] No empty cooking slots")
	return false

## Get interaction prompt for UI
func get_interact_prompt() -> String:
	# Check if any slot has food ready to take
	for slot in cooking_slots:
		if slot.state == CookState.COOKED:
			return "Take cooked meat [E]"
		elif slot.state == CookState.BURNED:
			return "Take charcoal [E]"

	# Check if we can add more food
	for slot in cooking_slots:
		if slot.state == CookState.EMPTY:
			return "Add meat to cook [E]"

	return "Cooking..."

## Add raw item to a cooking slot
func add_item_to_cook(item_name: String) -> int:
	if not COOKING_RECIPES.has(item_name):
		print("[CookingStation] %s cannot be cooked" % item_name)
		return -1

	# Find empty slot
	for slot_idx in cooking_slots.size():
		var slot = cooking_slots[slot_idx]
		if slot.state == CookState.EMPTY:
			slot.item = item_name
			slot.progress = 0.0
			slot.cooked_item = COOKING_RECIPES[item_name]
			slot.state = CookState.RAW

			# Show visual
			if slot_idx < slot_visuals.size():
				slot_visuals[slot_idx].visible = true
				_update_slot_visual(slot_idx)

			print("[CookingStation] Started cooking %s in slot %d" % [item_name, slot_idx])
			cooking_started.emit(slot_idx, item_name)
			return slot_idx

	print("[CookingStation] No empty cooking slots")
	return -1

## Remove item from a slot
func remove_item(slot_idx: int) -> String:
	if slot_idx < 0 or slot_idx >= cooking_slots.size():
		return ""

	var slot = cooking_slots[slot_idx]
	if slot.state == CookState.EMPTY:
		return ""

	var result_item = ""
	match slot.state:
		CookState.RAW, CookState.COOKING:
			result_item = slot.item  # Return raw if not done
		CookState.COOKED:
			result_item = slot.cooked_item
		CookState.BURNED:
			result_item = "charcoal"

	# Clear slot
	slot.item = ""
	slot.progress = 0.0
	slot.cooked_item = ""
	slot.state = CookState.EMPTY

	# Hide visual
	if slot_idx < slot_visuals.size():
		slot_visuals[slot_idx].visible = false

	print("[CookingStation] Removed %s from slot %d" % [result_item, slot_idx])
	return result_item

func _update_slot_visual(slot_idx: int) -> void:
	if slot_idx >= slot_visuals.size():
		return

	var slot = cooking_slots[slot_idx]
	var visual = slot_visuals[slot_idx]
	var mat = visual.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		return

	match slot.state:
		CookState.RAW:
			mat.albedo_color = COLOR_RAW
		CookState.COOKING:
			# Lerp from raw to cooked based on progress
			var cook_progress = slot.progress / COOKING_TIME
			mat.albedo_color = COLOR_RAW.lerp(COLOR_COOKED, cook_progress)
		CookState.COOKED:
			# Lerp from cooked to burned
			var burn_progress = (slot.progress - COOKING_TIME) / (BURN_TIME - COOKING_TIME)
			mat.albedo_color = COLOR_COOKED.lerp(COLOR_BURNED, burn_progress * 0.5)  # Start darkening
		CookState.BURNED:
			mat.albedo_color = COLOR_BURNED

## Get cooking progress for a slot (0.0 to 1.0 for cooking phase)
func get_slot_progress(slot_idx: int) -> float:
	if slot_idx < 0 or slot_idx >= cooking_slots.size():
		return 0.0
	var slot = cooking_slots[slot_idx]
	if slot.state == CookState.EMPTY:
		return 0.0
	return min(slot.progress / COOKING_TIME, 1.0)

## Get burn progress for a slot (0.0 to 1.0 after cooked)
func get_burn_progress(slot_idx: int) -> float:
	if slot_idx < 0 or slot_idx >= cooking_slots.size():
		return 0.0
	var slot = cooking_slots[slot_idx]
	if slot.progress < COOKING_TIME:
		return 0.0
	return min((slot.progress - COOKING_TIME) / (BURN_TIME - COOKING_TIME), 1.0)

## Check if slot has a cooked item ready
func is_slot_done(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= cooking_slots.size():
		return false
	return cooking_slots[slot_idx].state == CookState.COOKED

## Check if slot is burned
func is_slot_burned(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= cooking_slots.size():
		return false
	return cooking_slots[slot_idx].state == CookState.BURNED

## Get slot state
func get_slot_state(slot_idx: int) -> int:
	if slot_idx < 0 or slot_idx >= cooking_slots.size():
		return CookState.EMPTY
	return cooking_slots[slot_idx].state

## Check if station is near a lit fireplace
func check_fire_proximity() -> void:
	var fireplaces = get_tree().get_nodes_in_group("fireplace")
	is_over_fire = false

	for fireplace in fireplaces:
		if not is_instance_valid(fireplace):
			continue
		var distance = global_position.distance_to(fireplace.global_position)
		if distance < 1.5:
			if fireplace.get("is_lit") != null:
				is_over_fire = fireplace.is_lit
			else:
				is_over_fire = true
			break

func _physics_process(_delta: float) -> void:
	check_fire_proximity()

## Serialize for network/save
func get_cooking_data() -> Array:
	var data: Array = []
	for slot in cooking_slots:
		data.append({
			"item": slot.item,
			"progress": slot.progress,
			"cooked_item": slot.cooked_item,
			"state": slot.state
		})
	return data

## Deserialize from network/save
func set_cooking_data(data: Array) -> void:
	for i in data.size():
		if i < MAX_SLOTS:
			cooking_slots[i] = data[i].duplicate()
			if cooking_slots[i].state != CookState.EMPTY:
				if i < slot_visuals.size():
					slot_visuals[i].visible = true
					_update_slot_visual(i)

## Sound helper functions
var _should_sizzle: bool = false

func _start_sizzle() -> void:
	_should_sizzle = true
	if sizzle_player and not sizzle_player.playing:
		sizzle_player.play()

func _stop_sizzle() -> void:
	_should_sizzle = false
	if sizzle_player and sizzle_player.playing:
		sizzle_player.stop()

func _on_sizzle_finished() -> void:
	# Loop the sizzle sound if we should still be sizzling
	if _should_sizzle and sizzle_player:
		sizzle_player.play()

func _play_complete_sound() -> void:
	if complete_player:
		complete_player.play()

func _play_burn_sound() -> void:
	if burn_player:
		burn_player.play()
