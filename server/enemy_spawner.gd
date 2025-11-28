extends Node

## EnemySpawner - Server-side enemy spawning system
## Spawns enemies naturally around players
## SERVER-AUTHORITATIVE: Broadcasts enemy state to all clients at 10Hz

# Spawn parameters
const SPAWN_CHECK_INTERVAL: float = 10.0  # Check for spawns every 10 seconds
const MIN_SPAWN_DISTANCE: float = 20.0    # Minimum distance from player
const MAX_SPAWN_DISTANCE: float = 40.0    # Maximum distance from player
const MAX_ENEMIES_PER_PLAYER: int = 3     # Max enemies per player in the area

# State sync parameters
const STATE_SYNC_INTERVAL: float = 0.1   # 10Hz state broadcast

# Enemy scenes
const GAHNOME_SCENE = preload("res://shared/enemies/gahnome.tscn")

# Tracking
var spawn_timer: float = 0.0
var state_sync_timer: float = 0.0
var spawned_enemies: Array[Node] = []
var enemy_paths: Dictionary = {}  # Node -> NodePath (cached for performance)

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

	# Update state sync timer
	state_sync_timer += delta

	if state_sync_timer >= STATE_SYNC_INTERVAL:
		state_sync_timer = 0.0
		_broadcast_enemy_states()

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
	# Validate and fix spawn position
	# Don't spawn if player Y is invalid (fell through world or died)
	if player.global_position.y < -50 or player.global_position.y > 500:
		return  # Skip spawning for invalid player positions

	# Get terrain world to check for collision
	var terrain_world = null
	if server_node and server_node.has_node("TerrainWorld"):
		terrain_world = server_node.get_node("TerrainWorld")

	# Try multiple times to find a valid spawn position with terrain collision
	for attempt in range(5):
		var angle = randf() * TAU
		# Start closer for first attempts, go further if needed
		var distance = randf_range(MIN_SPAWN_DISTANCE * (0.5 + attempt * 0.1), MAX_SPAWN_DISTANCE * (0.5 + attempt * 0.1))

		var spawn_offset = Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)

		var spawn_position = player.global_position + spawn_offset

		# Query actual terrain height at spawn position (not player's height!)
		if terrain_world and terrain_world.has_method("get_terrain_height_at"):
			var terrain_height = terrain_world.get_terrain_height_at(Vector2(spawn_position.x, spawn_position.z))
			spawn_position.y = terrain_height + 1.0  # Spawn 1m above actual ground
		else:
			# Fallback: use player's Y (less accurate for hilly terrain)
			spawn_position.y = player.global_position.y + 1.0

		# Check if terrain collision exists at this position
		if terrain_world and terrain_world.has_method("has_collision_at_position"):
			if terrain_world.has_collision_at_position(spawn_position):
				# Valid spawn position with collision - spawn the enemy
				_spawn_enemy(GAHNOME_SCENE, spawn_position)
				return
		else:
			# No terrain world check available, spawn anyway (fallback)
			_spawn_enemy(GAHNOME_SCENE, spawn_position)
			return

	# All attempts failed - don't spawn (terrain not loaded yet)

## Spawn an enemy at a position
func _spawn_enemy(enemy_scene: PackedScene, position: Vector3) -> void:
	var enemy = enemy_scene.instantiate()

	# Add to world container FIRST (before setting global_position)
	if server_node and server_node.has_node("World"):
		var world_container = server_node.get_node("World")
		world_container.add_child(enemy)

		# NOW we can set global_position (node is in the tree)
		enemy.global_position = position

		# Update spawn reference values (since _ready runs before position is set)
		if "spawn_y" in enemy:
			enemy.spawn_y = position.y
		if "last_valid_position" in enemy:
			enemy.last_valid_position = position

		# Track enemy and cache its path
		spawned_enemies.append(enemy)
		enemy_paths[enemy] = enemy.get_path()

		# Connect death signal
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)

		var enemy_name = enemy.enemy_name if "enemy_name" in enemy else "Enemy"
		print("[EnemySpawner] Spawned %s at %s" % [enemy_name, position])

		# Broadcast enemy spawn to all clients
		var enemy_path = enemy_paths[enemy]
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
	var enemy_path = enemy_paths.get(enemy, enemy.get_path())
	NetworkManager.rpc_despawn_enemy.rpc(enemy_path)

	# Clean up tracking
	if enemy in spawned_enemies:
		spawned_enemies.erase(enemy)
	if enemy in enemy_paths:
		enemy_paths.erase(enemy)

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
		if enemy in enemy_paths:
			enemy_paths.erase(enemy)

## Broadcast all enemy states to clients (called at 10Hz)
## Uses compact format: { "path_string": [px, py, pz, rot, state, hp], ... }
func _broadcast_enemy_states() -> void:
	if spawned_enemies.is_empty():
		return

	var states: Dictionary = {}

	for enemy in spawned_enemies:
		if not enemy or not is_instance_valid(enemy):
			continue
		if enemy.is_dead:
			continue
		if not enemy.has_method("get_sync_state"):
			continue

		# Get cached path
		var path = enemy_paths.get(enemy)
		if not path:
			continue

		# Get enemy state as compact array
		var state = enemy.get_sync_state()
		states[str(path)] = state

	# Broadcast to all clients
	if not states.is_empty():
		NetworkManager.rpc_update_enemy_states.rpc(states)

## Spawn enemy manually at a position (for testing/debugging)
func spawn_enemy_at(position: Vector3, enemy_type: String = "gahnome") -> void:
	match enemy_type:
		"gahnome":
			_spawn_enemy(GAHNOME_SCENE, position)
		_:
			print("[EnemySpawner] Unknown enemy type: %s" % enemy_type)
