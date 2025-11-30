class_name EnemyHealth
extends RefCounted

## EnemyHealth - Handles enemy health, damage, and death

signal died

var enemy: CharacterBody3D

var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false

# Loot table
var loot_table: Array = []

func _init(e: CharacterBody3D) -> void:
	enemy = e

# =============================================================================
# INITIALIZATION
# =============================================================================

## Set max health
func set_max_health(value: float) -> void:
	max_health = value
	health = value

## Set loot table
func set_loot_table(table: Array) -> void:
	loot_table = table

# =============================================================================
# DAMAGE
# =============================================================================

## Take damage
func take_damage(damage: float, attacker_id: int = -1, knockback: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	health -= damage
	print("[Enemy] Took %.1f damage, health: %.1f/%.1f" % [damage, health, max_health])

	# Apply knockback
	if knockback.length() > 0:
		enemy.velocity += knockback

	# Update health bar
	if enemy.health_bar:
		enemy.health_bar.update_health(health, max_health)

	# Show damage effect
	if enemy.has_method("show_damage_effect"):
		enemy.show_damage_effect(damage)

	# Check for death
	if health <= 0:
		die()

## Get health percentage
func get_health_percent() -> float:
	return health / max_health if max_health > 0 else 0.0

# =============================================================================
# DEATH
# =============================================================================

## Handle death
func die() -> void:
	if is_dead:
		return

	is_dead = true
	health = 0

	print("[Enemy] Died!")

	# Notify via signal
	died.emit()

	# Drop loot
	drop_loot()

	# Play death effect
	if enemy.has_method("play_death_effect"):
		enemy.play_death_effect()

	# Notify server if host
	if enemy.is_host:
		notify_death()

	# Queue for removal (with delay for death animation)
	var timer = enemy.get_tree().create_timer(2.0)
	timer.timeout.connect(func(): enemy.queue_free() if is_instance_valid(enemy) else null)

## Notify server of death
func notify_death() -> void:
	if not enemy.is_host:
		return

	var loot_data = generate_loot_data()
	NetworkManager.rpc_notify_enemy_died.rpc_id(1, enemy.network_id, loot_data)

# =============================================================================
# LOOT
# =============================================================================

## Drop loot items
func drop_loot() -> void:
	if loot_table.is_empty():
		return

	for loot_entry in loot_table:
		var item_id = loot_entry.get("item_id", "")
		var chance = loot_entry.get("chance", 1.0)
		var min_amount = loot_entry.get("min", 1)
		var max_amount = loot_entry.get("max", 1)

		if randf() <= chance:
			var amount = randi_range(min_amount, max_amount)
			spawn_loot_item(item_id, amount)

## Spawn a loot item
func spawn_loot_item(item_id: String, amount: int) -> void:
	var ResourceItem = preload("res://shared/environmental/resource_item.tscn")
	var item = ResourceItem.instantiate()

	item.item_id = item_id
	item.quantity = amount

	# Random position around enemy
	var offset = Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1))
	item.global_position = enemy.global_position + offset

	enemy.get_tree().root.add_child(item)

## Generate loot data for network sync
func generate_loot_data() -> Array:
	var drops = []

	for loot_entry in loot_table:
		var item_id = loot_entry.get("item_id", "")
		var chance = loot_entry.get("chance", 1.0)
		var min_amount = loot_entry.get("min", 1)
		var max_amount = loot_entry.get("max", 1)

		if randf() <= chance:
			var amount = randi_range(min_amount, max_amount)
			drops.append({
				"item_id": item_id,
				"quantity": amount
			})

	return drops
