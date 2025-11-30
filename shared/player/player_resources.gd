class_name PlayerResources
extends RefCounted

## PlayerResources - Manages stamina, brain power, health, damage, and death
## Handles resource regeneration, consumption, and player death/respawn

const PC = preload("res://shared/player/player_constants.gd")
const HitEffectScene = preload("res://shared/effects/hit_effect.tscn")
const ParryEffectScene = preload("res://shared/effects/parry_effect.tscn")

var player: CharacterBody3D

func _init(p: CharacterBody3D) -> void:
	player = p

# =============================================================================
# STAMINA
# =============================================================================

## Update stamina regeneration each frame
func update_stamina(delta: float) -> void:
	# God mode: unlimited stamina, never exhausted
	if player.god_mode:
		player.stamina = PC.MAX_STAMINA
		player.is_exhausted = false
		return

	# Regenerate stamina after delay
	player.stamina_regen_timer += delta

	if player.stamina_regen_timer >= PC.STAMINA_REGEN_DELAY:
		player.stamina = min(player.stamina + PC.STAMINA_REGEN_RATE * delta, PC.MAX_STAMINA)

	# Check for exhaustion recovery (need 10% stamina to recover)
	if player.is_exhausted and player.stamina >= PC.MAX_STAMINA * PC.EXHAUSTED_RECOVERY_THRESHOLD:
		player.is_exhausted = false
		print("[Player] Recovered from exhaustion")

## Consume stamina (returns true if enough stamina available)
func consume_stamina(amount: float) -> bool:
	# God mode: unlimited stamina
	if player.god_mode:
		return true
	if player.stamina >= amount:
		player.stamina -= amount
		player.stamina_regen_timer = 0.0  # Reset regen delay
		# Check if we just became exhausted (stamina depleted)
		if player.stamina <= 0:
			player.stamina = 0
			if not player.is_exhausted:
				player.is_exhausted = true
				print("[Player] Exhausted! Must recover stamina before sprinting/attacking")
		return true
	else:
		# Failed to consume - become exhausted if stamina is very low
		if player.stamina < amount and not player.is_exhausted:
			player.is_exhausted = true
			print("[Player] Exhausted! Not enough stamina")
		return false

# =============================================================================
# BRAIN POWER (MAGIC)
# =============================================================================

## Update brain power regeneration each frame
func update_brain_power(delta: float) -> void:
	# God mode: unlimited brain power
	if player.god_mode:
		player.brain_power = PC.MAX_BRAIN_POWER
		return

	# Regenerate brain power after delay
	player.brain_power_regen_timer += delta

	if player.brain_power_regen_timer >= PC.BRAIN_POWER_REGEN_DELAY:
		player.brain_power = min(player.brain_power + PC.BRAIN_POWER_REGEN_RATE * delta, PC.MAX_BRAIN_POWER)

## Consume brain power (returns true if enough brain power available)
func consume_brain_power(amount: float) -> bool:
	# God mode: unlimited brain power
	if player.god_mode:
		return true
	if player.brain_power >= amount:
		player.brain_power -= amount
		player.brain_power_regen_timer = 0.0  # Reset regen delay
		return true
	return false

# =============================================================================
# HEALTH & DAMAGE
# =============================================================================

## Take damage (with blocking/parry support)
func take_damage(damage: float, attacker_id: int = -1, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if player.is_dead:
		return

	var final_damage = damage
	var was_parried = false

	# Apply stun damage multiplier if stunned
	if player.is_stunned:
		final_damage *= PC.STUN_DAMAGE_MULTIPLIER
		print("[Player] Taking extra damage while stunned! (%.1fx multiplier)" % PC.STUN_DAMAGE_MULTIPLIER)

	# Check for blocking/parrying
	if player.is_blocking:
		var shield_data = null
		var weapon_data = null
		if player.equipment:
			shield_data = player.equipment.get_equipped_shield()
			weapon_data = player.equipment.get_equipped_weapon()

		# Default to fists if no weapon equipped
		if not weapon_data:
			weapon_data = ItemDatabase.get_item("fists")

		# Get parry window from weapon
		var parry_window = weapon_data.parry_window if weapon_data else 0.15

		# Check for parry (within parry window)
		if player.block_timer <= parry_window:
			print("[Player] PARRY! Negating damage and stunning attacker%s" % (" (fists)" if not shield_data else " (shield)"))
			was_parried = true
			final_damage = 0

			# Spawn parry effect
			_spawn_parry_effect()

			# Apply stun to attacker
			_apply_stun_to_attacker(attacker_id)
		else:
			# Normal block
			if shield_data:
				# Shield blocking (high reduction)
				final_damage = max(0, damage - shield_data.block_armor)
				consume_stamina(shield_data.stamina_drain_per_hit)
				print("[Player] Blocked with shield! Damage reduced from %d to %d" % [damage, final_damage])
			else:
				# Fist blocking (moderate reduction)
				final_damage = damage * (1.0 - PC.BLOCK_DAMAGE_REDUCTION)
				consume_stamina(10.0)  # Fist blocking costs more stamina
				print("[Player] Blocked with fists! Damage reduced from %d to %d" % [damage, final_damage])

	# Apply damage
	player.health -= final_damage
	print("[Player] Took %d damage, health: %d" % [final_damage, player.health])

	# Spawn hit effect if damage was dealt
	if final_damage > 0:
		_spawn_hit_effect()

	# Apply knockback (if not parried)
	if not was_parried and knockback_dir.length() > 0:
		var knockback_mult = 2.0  # Base knockback
		if player.is_blocking:
			knockback_mult = 0.5  # Blocking greatly reduces knockback
		player.velocity += knockback_dir * knockback_mult

	if player.health <= 0:
		player.health = 0
		die()

## Apply stun to attacker (when parry succeeds)
func _apply_stun_to_attacker(attacker_id: int) -> void:
	if attacker_id == -1:
		return

	# Find attacker by instance ID
	var attacker = instance_from_id(attacker_id)
	if not attacker or not is_instance_valid(attacker):
		return

	# Apply stun if the attacker has the apply_stun method
	if attacker.has_method("apply_stun"):
		attacker.apply_stun()
		print("[Player] Stunned attacker: %s" % attacker.name)

## Spawn hit particle effect at player position
func _spawn_hit_effect() -> void:
	var pos = player.global_position + Vector3(0, 1.0, 0)  # Chest height
	var effect = HitEffectScene.instantiate()
	player.get_tree().current_scene.add_child(effect)
	effect.global_position = pos

	# Play player hurt sound
	SoundManager.play_sound_varied("player_hurt", pos)

## Spawn parry particle effect at player position
func _spawn_parry_effect() -> void:
	var pos = player.global_position + Vector3(0, 1.2, 0)  # Shield height
	var effect = ParryEffectScene.instantiate()
	player.get_tree().current_scene.add_child(effect)
	effect.global_position = pos

	# Play parry sound
	SoundManager.play_sound("parry", pos)

# =============================================================================
# STUN
# =============================================================================

## Apply stun to this player
func apply_stun(duration: float = PC.STUN_DURATION) -> void:
	player.is_stunned = true
	player.stun_timer = duration
	print("[Player] Stunned for %.1f seconds!" % duration)

## Update stun timer
func update_stun(delta: float) -> void:
	if player.is_stunned:
		player.stun_timer -= delta
		if player.stun_timer <= 0:
			player.is_stunned = false
			player.stun_timer = 0
			# Reset body rotation after stun
			if player.body_container:
				player.body_container.rotation = Vector3.ZERO

# =============================================================================
# DEATH & RESPAWN
# =============================================================================

## Handle player death
func die() -> void:
	if player.is_dead:
		return

	player.is_dead = true
	print("[Player] Player died!")

	# Play death sound
	SoundManager.play_sound("player_hurt", player.global_position)

	# Disable physics
	player.set_physics_process(false)

	# Play death animation (programmatic - fall over)
	if player.body_container:
		var tween = player.create_tween()
		tween.tween_property(player.body_container, "rotation:x", PI / 2, 1.0)
		tween.parallel().tween_property(player.body_container, "position:y", -0.5, 1.0)

	# Notify server of death
	if player.is_local_player and NetworkManager.is_client:
		NetworkManager.rpc_player_died.rpc_id(1)

	# Respawn after delay
	if player.is_local_player:
		_start_respawn_timer()

func _start_respawn_timer() -> void:
	await player.get_tree().create_timer(5.0).timeout
	request_respawn()

## Request respawn from server
func request_respawn() -> void:
	if not player.is_local_player:
		return

	print("[Player] Requesting respawn...")
	if NetworkManager.is_client:
		NetworkManager.rpc_request_respawn.rpc_id(1)

## Respawn player (called by server via RPC)
func respawn_at(spawn_position: Vector3) -> void:
	player.is_dead = false
	player.health = PC.MAX_HEALTH
	player.stamina = PC.MAX_STAMINA
	player.brain_power = PC.MAX_BRAIN_POWER
	player.global_position = spawn_position
	player.velocity = Vector3.ZERO

	print("[Player] Player respawned at %s!" % spawn_position)

	# Reset body rotation and position
	if player.body_container:
		player.body_container.rotation = Vector3.ZERO
		player.body_container.position = Vector3.ZERO

	# Reset fall timer
	player.fall_time_below_ground = 0.0

	# Re-enable physics
	player.set_physics_process(true)
