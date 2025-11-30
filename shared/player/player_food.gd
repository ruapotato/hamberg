extends Node

## PlayerFood - Valheim-style food buff system
## Manages active food buffs and calculates stat bonuses

const PC = preload("res://shared/player/player_constants.gd")
const FoodData = preload("res://shared/food_data.gd")

signal food_changed()  # Emitted when food buffs change
signal food_expired(food_name: String)  # Emitted when a food buff expires

# Active food buffs: Array of {food_id: String, remaining_time: float, food_data: FoodData}
var active_foods: Array[Dictionary] = []

# Reference to parent player
var player: Node = null

func _ready() -> void:
	player = get_parent()

func _process(delta: float) -> void:
	if active_foods.is_empty():
		return

	var foods_to_remove: Array[int] = []
	var total_regen: float = 0.0

	# Decay all active foods and sum up regen
	for i in active_foods.size():
		active_foods[i].remaining_time -= delta

		if active_foods[i].remaining_time <= 0:
			foods_to_remove.append(i)
		elif active_foods[i].food_data:
			# Sum up health regen from all active foods
			total_regen += active_foods[i].food_data.heal_per_second

	# Apply health regeneration
	if total_regen > 0.0 and player:
		_apply_health_regen(total_regen * delta)

	# Remove expired foods (in reverse order to maintain indices)
	if not foods_to_remove.is_empty():
		foods_to_remove.reverse()
		for idx in foods_to_remove:
			var expired_food = active_foods[idx]
			print("[PlayerFood] %s buff expired" % expired_food.food_id)
			food_expired.emit(expired_food.food_id)
			active_foods.remove_at(idx)

		food_changed.emit()
		_update_player_stats(true)  # true = food expired, scale health down

## Attempt to eat a food item
## Returns true if successfully eaten, false if couldn't (e.g., already have 3 foods of same type)
func eat_food(food_id: String) -> bool:
	# Get food data from ItemDatabase
	var food_data = ItemDatabase.get_item(food_id)
	if not food_data or not food_data is FoodData:
		print("[PlayerFood] %s is not a valid food item" % food_id)
		return false

	# Check if we already have this food active - block eating same food
	for i in active_foods.size():
		if active_foods[i].food_id == food_id:
			print("[PlayerFood] Cannot eat %s - already active (%.0fs remaining)" % [food_id, active_foods[i].remaining_time])
			return false

	# Check if we have room for new food
	if active_foods.size() >= PC.MAX_FOOD_SLOTS:
		print("[PlayerFood] Cannot eat %s - already have %d foods active" % [food_id, PC.MAX_FOOD_SLOTS])
		return false

	# Store old max health BEFORE adding the food for percentage calculation
	var old_max_health = get_max_health()

	# Add new food buff
	active_foods.append({
		"food_id": food_id,
		"remaining_time": food_data.duration,
		"food_data": food_data
	})

	print("[PlayerFood] Ate %s (+%.0f HP, +%.0f Stam, +%.0f BP, +%.1f HP/s for %.0fs)" % [
		food_id, food_data.health_bonus, food_data.stamina_bonus, food_data.bp_bonus,
		food_data.heal_per_second, food_data.duration
	])

	food_changed.emit()
	_update_player_stats_with_old_max(old_max_health)
	return true

## Get total health bonus from all active foods
func get_health_bonus() -> float:
	var bonus: float = 0.0
	for food in active_foods:
		if food.food_data:
			bonus += food.food_data.health_bonus
	return bonus

## Get total stamina bonus from all active foods
func get_stamina_bonus() -> float:
	var bonus: float = 0.0
	for food in active_foods:
		if food.food_data:
			bonus += food.food_data.stamina_bonus
	return bonus

## Get total brain power bonus from all active foods
func get_bp_bonus() -> float:
	var bonus: float = 0.0
	for food in active_foods:
		if food.food_data:
			bonus += food.food_data.bp_bonus
	return bonus

## Get current max health (base + food bonuses)
func get_max_health() -> float:
	return min(PC.BASE_HEALTH + get_health_bonus(), PC.MAX_HEALTH)

## Get current max stamina (base + food bonuses)
func get_max_stamina() -> float:
	return min(PC.BASE_STAMINA + get_stamina_bonus(), PC.MAX_STAMINA)

## Get current max brain power (base + food bonuses)
func get_max_brain_power() -> float:
	return min(PC.BASE_BRAIN_POWER + get_bp_bonus(), PC.MAX_BRAIN_POWER)

## Update player stats when food expires (max stats decrease)
func _update_player_stats(food_expired: bool = false) -> void:
	if not player:
		return

	# When food expires, scale health down to preserve percentage
	if player.has_method("scale_health_to_new_max"):
		player.scale_health_to_new_max(get_max_health())

	# Clamp stamina and brain power to new maximums
	if player.has_method("clamp_stats_to_max"):
		player.clamp_stats_to_max()

## Update player stats with known old max (used when eating food)
func _update_player_stats_with_old_max(old_max_health: float) -> void:
	if not player:
		return

	# Scale health to preserve percentage using the old max we stored
	if player.has_method("scale_health_with_old_max"):
		player.scale_health_with_old_max(old_max_health, get_max_health())

	# Clamp stamina and brain power to new maximums
	if player.has_method("clamp_stats_to_max"):
		player.clamp_stats_to_max()

## Apply health regeneration from food
func _apply_health_regen(amount: float) -> void:
	if not player:
		return

	var max_health = get_max_health()
	if "health" in player:
		player.health = min(player.health + amount, max_health)

## Get info about active foods for UI
func get_active_foods_info() -> Array[Dictionary]:
	var info: Array[Dictionary] = []
	for food in active_foods:
		info.append({
			"food_id": food.food_id,
			"remaining_time": food.remaining_time,
			"duration": food.food_data.duration if food.food_data else 600.0,
			"health_bonus": food.food_data.health_bonus if food.food_data else 0.0,
			"stamina_bonus": food.food_data.stamina_bonus if food.food_data else 0.0,
			"bp_bonus": food.food_data.bp_bonus if food.food_data else 0.0,
		})
	return info

## Clear all food buffs (e.g., on death)
func clear_all_foods() -> void:
	active_foods.clear()
	food_changed.emit()
	_update_player_stats()

## Serialize for saving
func get_save_data() -> Array:
	var data: Array = []
	for food in active_foods:
		data.append({
			"food_id": food.food_id,
			"remaining_time": food.remaining_time
		})
	return data

## Deserialize from save
func load_save_data(data: Array) -> void:
	active_foods.clear()

	for food_save in data:
		var food_data = ItemDatabase.get_item(food_save.food_id)
		if food_data and food_data is FoodData:
			active_foods.append({
				"food_id": food_save.food_id,
				"remaining_time": food_save.remaining_time,
				"food_data": food_data
			})

	food_changed.emit()
	_update_player_stats()
