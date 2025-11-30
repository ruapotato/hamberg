class_name PlayerBlocking
extends RefCounted

## PlayerBlocking - Handles block and parry mechanics
## Shield blocking reduces damage, parrying stuns the attacker

const PC = preload("res://shared/player/player_constants.gd")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# BLOCKING
# =============================================================================

## Handle block input (right mouse button)
func handle_block_input(is_pressed: bool) -> void:
	if not player.is_local_player or player.is_dead:
		return

	if is_pressed and not player.is_blocking:
		# Start blocking
		player.is_blocking = true
		player.block_timer = 0.0
		player.block_start_time = Time.get_ticks_msec() / 1000.0
		print("[Player] Started blocking")
	elif not is_pressed and player.is_blocking:
		# Stop blocking
		player.is_blocking = false
		print("[Player] Stopped blocking")

## Update block timer
func update_block(delta: float) -> void:
	if player.is_blocking:
		player.block_timer += delta

## Check if player can parry (within parry window)
func can_parry() -> bool:
	if not player.is_blocking:
		return false

	# Get parry window from equipped weapon/shield
	var parry_window = PC.PARRY_WINDOW

	if player.equipment:
		var weapon_data = player.equipment.get_equipped_weapon()
		if weapon_data and "parry_window" in weapon_data:
			parry_window = weapon_data.parry_window

	return player.block_timer <= parry_window

## Get block damage reduction multiplier (1.0 = no reduction, 0.0 = full block)
func get_block_reduction() -> float:
	if not player.is_blocking:
		return 1.0

	if player.equipment:
		var shield_data = player.equipment.get_equipped_shield()
		if shield_data:
			# Shield provides block_armor as flat reduction
			return 0.0  # Shield uses flat armor, not percentage

	# Fist blocking - percentage reduction
	return 1.0 - PC.BLOCK_DAMAGE_REDUCTION

## Get movement speed multiplier while blocking
func get_block_speed_multiplier() -> float:
	if player.is_blocking:
		return PC.BLOCK_SPEED_MULTIPLIER
	return 1.0
