extends Node

## EnemySpawner - Server-side enemy spawning system
## Spawns enemies naturally around players

# Spawn parameters
const SPAWN_CHECK_INTERVAL: float = 10.0  # Check for spawns every 10 seconds
const MIN_SPAWN_DISTANCE: float = 20.0    # Minimum distance from player
const MAX_SPAWN_DISTANCE: float = 40.0    # Maximum distance from player
const MAX_ENEMIES_PER_PLAYER: int = 3     # Max enemies per player in the area

# Enemy scenes
const GAHNOME_SCENE = preload("res://shared/enemies/gahnome.tscn")

# Tracking
var spawn_timer: float = 0.0
var spawned_enemies: Array[Node] = []

# Reference to server node
var server_node: Node = null

func _ready() -> void:
	# Get server reference
	server_node = get_parent()
	print("[EnemySpawner] Enemy spawner initialized")

func _process(delta: float) -> void:
	# Only run on server
	if not multiplayer.is_server():
		return

	# Update spawn timer
	spawn_timer += delta

	if spawn_timer >= SPAWN_CHECK_INTERVAL:
		spawn_timer = 0.0
		_check_spawns()

	# Clean up dead enemies
	_cleanup_dead_enemies()

## Check if we should spawn enemies
func _check_spawns() -> void:
	if not server_node or not "spawned_players" in server_node:
		return

	var players = server_node.spawned_players

	# For each player, check if we need to spawn enemies
	for peer_id in players:
		var player = players[peer_id]
		if not player or not is_instance_valid(player):
			continue

		# Count enemies near this player
		var nearby_enemies = _count_nearby_enemies(player.global_position)

		# Spawn enemies if below threshold
		if nearby_enemies < MAX_ENEMIES_PER_PLAYER:
			var enemies_to_spawn = MAX_ENEMIES_PER_PLAYER - nearby_enemies
			for i in range(enemies_to_spawn):
				_spawn_enemy_near_player(player)

## Count enemies near a position
func _count_nearby_enemies(position: Vector3) -> int:
	var count = 0
	for enemy in spawned_enemies:
		if enemy and is_instance_valid(enemy):
			var distance = enemy.global_position.distance_to(position)
			if distance <= MAX_SPAWN_DISTANCE:
				count += 1
	return count

## Spawn an enemy near a player
func _spawn_enemy_near_player(player: Node) -> void:
	# Random spawn position around player
	var angle = randf() * TAU
	var distance = randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)

	var spawn_offset = Vector3(
		cos(angle) * distance,
		0,
		sin(angle) * distance
	)

	var spawn_position = player.global_position + spawn_offset

	# Validate and fix spawn position
	# Don't spawn if player Y is invalid (fell through world or died)
	if player.global_position.y < -50 or player.global_position.y > 500:
		return  # Skip spawning for invalid player positions

	# Keep player's Y position (they're already on the ground) and spawn slightly above
	spawn_position.y = player.global_position.y + 1.0  # Spawn 1m above ground, gentle drop

	# Spawn the enemy
	_spawn_enemy(GAHNOME_SCENE, spawn_position)

## Spawn an enemy at a position
func _spawn_enemy(enemy_scene: PackedScene, position: Vector3) -> void:
	var enemy = enemy_scene.instantiate()

	# Add to world container FIRST (before setting global_position)
	if server_node and server_node.has_node("World"):
		var world_container = server_node.get_node("World")
		world_container.add_child(enemy)

		# NOW we can set global_position (node is in the tree)
		enemy.global_position = position

		# Track enemy
		spawned_enemies.append(enemy)

		# Connect death signal
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)

		var enemy_name = enemy.enemy_name if "enemy_name" in enemy else "Enemy"
		print("[EnemySpawner] Spawned %s at %s" % [enemy_name, position])

		# Broadcast enemy spawn to all clients
		var enemy_path = enemy.get_path()
		# IMPORTANT: Use enemy_name (from exported var) not node.name (which changes at runtime)
		var enemy_type = enemy_name  # Always "Gahnome", not "@CharacterBody3D@5366"
		var pos_array = [position.x, position.y, position.z]
		NetworkManager.rpc_spawn_enemy.rpc(enemy_path, enemy_type, pos_array, enemy_name)
	else:
		print("[EnemySpawner] ERROR: WorldContainer not found!")
		enemy.queue_free()

## Handle enemy death
func _on_enemy_died(enemy: Node) -> void:
	print("[EnemySpawner] Enemy died: %s" % enemy.name)

	# Broadcast enemy despawn to all clients
	var enemy_path = enemy.get_path()
	NetworkManager.rpc_despawn_enemy.rpc(enemy_path)

	# Enemy will free itself, just remove from tracking
	if enemy in spawned_enemies:
		spawned_enemies.erase(enemy)

## Clean up dead/invalid enemies
func _cleanup_dead_enemies() -> void:
	var to_remove: Array[Node] = []

	for enemy in spawned_enemies:
		if not enemy or not is_instance_valid(enemy):
			to_remove.append(enemy)
		elif "is_dead" in enemy and enemy.is_dead:
			to_remove.append(enemy)

	for enemy in to_remove:
		spawned_enemies.erase(enemy)

## Spawn enemy manually at a position (for testing/debugging)
func spawn_enemy_at(position: Vector3, enemy_type: String = "gahnome") -> void:
	match enemy_type:
		"gahnome":
			_spawn_enemy(GAHNOME_SCENE, position)
		_:
			print("[EnemySpawner] Unknown enemy type: %s" % enemy_type)
