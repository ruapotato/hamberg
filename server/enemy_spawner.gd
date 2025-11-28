extends Node

## EnemySpawner - Server-side enemy spawning system
## Spawns enemies naturally around players
## CLIENT-HOST MODEL:
## - One client is designated as "host" for each enemy
## - Host client runs full AI/physics using their terrain collision
## - Host sends position reports to server at 10Hz
## - Server relays host position to all other clients
## - Server handles health/damage (authoritative)

# Spawn parameters
const SPAWN_CHECK_INTERVAL: float = 10.0  # Check for spawns every 10 seconds
const MIN_SPAWN_DISTANCE: float = 40.0    # Minimum distance from player (far away)
const MAX_SPAWN_DISTANCE: float = 60.0    # Maximum distance from player (far away)
const MAX_ENEMIES_PER_PLAYER: int = 3     # Max enemies per player in the area
const BEHIND_PLAYER_BIAS: float = 0.7     # 70% chance to spawn behind player

# State sync parameters
const STATE_SYNC_INTERVAL: float = 0.1   # 10Hz position relay

# Enemy scenes
const GAHNOME_SCENE = preload("res://shared/enemies/gahnome.tscn")
const SPORELING_SCENE = preload("res://shared/enemies/sporeling.tscn")

# Animal scenes
const DEER_SCENE = preload("res://shared/animals/deer.tscn")
const PIG_SCENE = preload("res://shared/animals/pig.tscn")
const SHEEP_SCENE = preload("res://shared/animals/sheep.tscn")

# Biome-specific enemy types
const DARK_FOREST_BIOMES = ["dark_forest"]

# Biomes where animals can spawn
const ANIMAL_BIOMES = ["meadow", "valley", "dark_forest"]

# Animal spawn parameters (separate from enemies)
const ANIMAL_SPAWN_CHECK_INTERVAL: float = 15.0  # Check less frequently
const MAX_ANIMALS_PER_PLAYER: int = 2  # Fewer animals than enemies
var animal_spawn_timer: float = 0.0

# Tracking
var spawn_timer: float = 0.0
var state_sync_timer: float = 0.0
var spawned_enemies: Array[Node] = []
var enemy_paths: Dictionary = {}  # Node -> NodePath (cached for performance)
var enemy_network_ids: Dictionary = {}  # Node -> int (network ID)
var network_id_to_enemy: Dictionary = {}  # int -> Node (reverse lookup)
var next_network_id: int = 1  # Counter for generating unique network IDs

# Host tracking - which client is running AI for each enemy
var enemy_host_peers: Dictionary = {}  # network_id -> peer_id (who is hosting this enemy)

# Latest position reports from host clients (one per enemy)
# Format: { network_id: { position: Vector3, rotation_y: float, ai_state: int, timestamp: float }, ... }
var host_position_reports: Dictionary = {}
const REPORT_TIMEOUT: float = 0.5  # Discard reports older than 0.5 seconds

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

	# Update animal spawn timer
	animal_spawn_timer += delta

	if animal_spawn_timer >= ANIMAL_SPAWN_CHECK_INTERVAL:
		animal_spawn_timer = 0.0
		_check_animal_spawns()

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
				# The player that triggered the spawn becomes the host
				_spawn_enemy_near_player(player, peer_id)

## Count enemies near a position
func _count_nearby_enemies(position: Vector3) -> int:
	var count = 0
	for enemy in spawned_enemies:
		if enemy and is_instance_valid(enemy):
			var distance = enemy.global_position.distance_to(position)
			if distance <= MAX_SPAWN_DISTANCE:
				count += 1
	return count

## Spawn an enemy near a player (player becomes the host for this enemy)
func _spawn_enemy_near_player(player: Node, peer_id: int = 0) -> void:
	# Validate and fix spawn position
	# Don't spawn if player Y is invalid (fell through world or died)
	if player.global_position.y < -50 or player.global_position.y > 500:
		return  # Skip spawning for invalid player positions

	# Get terrain world to check for collision
	var terrain_world = null
	if server_node and server_node.has_node("TerrainWorld"):
		terrain_world = server_node.get_node("TerrainWorld")

	# Get player's backward direction angle (opposite of where they're looking)
	var player_backward_angle = player.rotation.y  # Behind player (+Z direction in local space)

	# Try multiple times to find a valid spawn position with terrain collision
	for attempt in range(5):
		# Prefer spawning behind the player
		var angle: float
		if randf() < BEHIND_PLAYER_BIAS:
			# Spawn behind player (within ~90 degree cone behind them)
			angle = player_backward_angle + randf_range(-PI/2, PI/2)
		else:
			# Spawn to the sides (not in front)
			var side = 1 if randf() > 0.5 else -1
			angle = player_backward_angle + side * randf_range(PI/2, PI * 0.8)

		# Use full distance range
		var distance = randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)

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

		# Get biome at spawn position to determine enemy type
		var biome = "valley"  # Default biome
		if terrain_world and terrain_world.has_method("get_biome_at"):
			biome = terrain_world.get_biome_at(Vector2(spawn_position.x, spawn_position.z))

		# Choose enemy scene based on biome
		var enemy_scene = GAHNOME_SCENE
		if biome in DARK_FOREST_BIOMES:
			enemy_scene = SPORELING_SCENE

		# Check if terrain collision exists at this position
		if terrain_world and terrain_world.has_method("has_collision_at_position"):
			if terrain_world.has_collision_at_position(spawn_position):
				# Valid spawn position with collision - spawn the enemy
				_spawn_enemy(enemy_scene, spawn_position, peer_id)
				return
		else:
			# No terrain world check available, spawn anyway (fallback)
			_spawn_enemy(enemy_scene, spawn_position, peer_id)
			return

	# All attempts failed - don't spawn (terrain not loaded yet)

## Spawn an enemy at a position with assigned host client
func _spawn_enemy(enemy_scene: PackedScene, position: Vector3, host_peer_id: int = 0) -> void:
	var enemy = enemy_scene.instantiate()

	# Assign network ID BEFORE adding to tree (so it's available in _ready)
	var net_id = next_network_id
	next_network_id += 1
	if "network_id" in enemy:
		enemy.network_id = net_id

	# Assign host peer ID
	if "host_peer_id" in enemy:
		enemy.host_peer_id = host_peer_id

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

		# Track enemy and cache its path + network ID
		spawned_enemies.append(enemy)
		enemy_paths[enemy] = enemy.get_path()
		enemy_network_ids[enemy] = net_id
		network_id_to_enemy[net_id] = enemy

		# Track host peer for this enemy
		enemy_host_peers[net_id] = host_peer_id

		# Initialize position report storage for this enemy
		host_position_reports[net_id] = {}

		# Connect death signal
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)

		var enemy_name = enemy.enemy_name if "enemy_name" in enemy else "Enemy"
		print("[EnemySpawner] Spawned %s at %s (network_id=%d, host_peer=%d)" % [enemy_name, position, net_id, host_peer_id])

		# Broadcast enemy spawn to all clients (include network_id AND host_peer_id in position array)
		var enemy_path = enemy_paths[enemy]
		# IMPORTANT: Use enemy_name (from exported var) not node.name (which changes at runtime)
		var enemy_type = enemy_name  # Always "Gahnome", not "@CharacterBody3D@5366"
		var pos_array = [position.x, position.y, position.z, net_id, host_peer_id]  # Include network_id and host_peer_id
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
	if enemy in enemy_network_ids:
		var net_id = enemy_network_ids[enemy]
		enemy_network_ids.erase(enemy)
		network_id_to_enemy.erase(net_id)
		enemy_host_peers.erase(net_id)
		host_position_reports.erase(net_id)

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
		if enemy in enemy_network_ids:
			var net_id = enemy_network_ids[enemy]
			enemy_network_ids.erase(enemy)
			network_id_to_enemy.erase(net_id)
			enemy_host_peers.erase(net_id)
			host_position_reports.erase(net_id)

## Broadcast all enemy states to clients (called at 10Hz)
## VALHEIM-STYLE: Server relays host client's position reports to all other clients
## Server is authoritative for health only
## Uses compact format: { "path_string": [px, py, pz, rot, state, hp, target_peer], ... }
func _broadcast_enemy_states() -> void:
	if spawned_enemies.is_empty():
		return

	var states: Dictionary = {}

	for enemy in spawned_enemies:
		if not enemy or not is_instance_valid(enemy):
			continue
		if enemy.is_dead:
			continue

		# Get network ID and cached path
		var net_id = enemy_network_ids.get(enemy, 0)
		var path = enemy_paths.get(enemy)
		if not path or net_id == 0:
			continue

		# Get host's position report (from client running AI)
		var report = host_position_reports.get(net_id, {})
		if report.is_empty():
			# No report from host yet - use enemy's spawn position
			states[str(path)] = [
				snappedf(enemy.global_position.x, 0.01),
				snappedf(enemy.global_position.y, 0.01),
				snappedf(enemy.global_position.z, 0.01),
				0.0,  # rotation
				0,    # ai_state (IDLE)
				snappedf(enemy.health if "health" in enemy else 50.0, 0.1),
				0,    # target_peer
			]
			continue

		# Check if report is stale
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - report.get("timestamp", 0.0) > REPORT_TIMEOUT:
			continue  # Skip stale reports

		# Combine host's position/state with server's authoritative health
		var hp = enemy.health if "health" in enemy else 50.0
		states[str(path)] = [
			snappedf(report.position.x, 0.01),
			snappedf(report.position.y, 0.01),
			snappedf(report.position.z, 0.01),
			snappedf(report.rotation_y, 0.01),
			report.ai_state,
			snappedf(hp, 0.1),
			report.target_peer,
		]

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

# ============================================================================
# HOST POSITION REPORTS SYSTEM
# ============================================================================

## Receive position report from host client
## Called via RPC from NetworkManager.rpc_report_enemy_position
func receive_enemy_position_report(peer_id: int, enemy_network_id: int, position: Vector3, rotation_y: float, ai_state: int, target_peer: int = 0) -> void:
	# Only accept reports from the designated host for this enemy
	var expected_host = enemy_host_peers.get(enemy_network_id, 0)
	if peer_id != expected_host:
		# Non-host sent a report - ignore it
		return

	# Store the host's report (including target for relay)
	host_position_reports[enemy_network_id] = {
		"position": position,
		"rotation_y": rotation_y,
		"ai_state": ai_state,
		"target_peer": target_peer,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}

## Get host position for an enemy (used during _broadcast_enemy_states)
func _get_host_position(net_id: int) -> Dictionary:
	var report = host_position_reports.get(net_id, {})
	if report.is_empty():
		return {}

	# Check if report is stale
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - report.get("timestamp", 0.0) > REPORT_TIMEOUT:
		return {}

	return report

## Get network ID for an enemy node
func get_enemy_network_id(enemy: Node) -> int:
	return enemy_network_ids.get(enemy, 0)

## Get host peer ID for an enemy
func get_enemy_host_peer(net_id: int) -> int:
	return enemy_host_peers.get(net_id, 0)

# ============================================================================
# ANIMAL SPAWNING SYSTEM
# ============================================================================

## Check if we should spawn animals
func _check_animal_spawns() -> void:
	if not server_node or not "spawned_players" in server_node:
		return

	var players = server_node.spawned_players

	# For each player, check if we need to spawn animals
	for peer_id in players:
		var player = players[peer_id]
		if not player or not is_instance_valid(player):
			continue

		# Count animals near this player
		var nearby_animals = _count_nearby_animals(player.global_position)

		# Spawn animals if below threshold
		if nearby_animals < MAX_ANIMALS_PER_PLAYER:
			var animals_to_spawn = MAX_ANIMALS_PER_PLAYER - nearby_animals
			for i in range(animals_to_spawn):
				_spawn_animal_near_player(player, peer_id)

## Count animals near a position
func _count_nearby_animals(position: Vector3) -> int:
	var count = 0
	for enemy in spawned_enemies:
		if enemy and is_instance_valid(enemy):
			# Check if this is an animal (in "animals" group)
			if enemy.is_in_group("animals"):
				var distance = enemy.global_position.distance_to(position)
				if distance <= MAX_SPAWN_DISTANCE:
					count += 1
	return count

## Spawn an animal near a player
func _spawn_animal_near_player(player: Node, peer_id: int = 0) -> void:
	# Validate player position
	if player.global_position.y < -50 or player.global_position.y > 500:
		return

	# Get terrain world
	var terrain_world = null
	if server_node and server_node.has_node("TerrainWorld"):
		terrain_world = server_node.get_node("TerrainWorld")

	# Get player's backward direction angle (opposite of where they're looking)
	var player_backward_angle = player.rotation.y  # Behind player (+Z direction in local space)

	# Try to find valid spawn position
	for attempt in range(5):
		# Prefer spawning behind the player
		var angle: float
		if randf() < BEHIND_PLAYER_BIAS:
			# Spawn behind player (within ~90 degree cone behind them)
			angle = player_backward_angle + randf_range(-PI/2, PI/2)
		else:
			# Spawn to the sides (not in front)
			var side = 1 if randf() > 0.5 else -1
			angle = player_backward_angle + side * randf_range(PI/2, PI * 0.8)

		# Use full distance range
		var distance = randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)

		var spawn_offset = Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)

		var spawn_position = player.global_position + spawn_offset

		# Get terrain height
		if terrain_world and terrain_world.has_method("get_terrain_height_at"):
			var terrain_height = terrain_world.get_terrain_height_at(Vector2(spawn_position.x, spawn_position.z))
			spawn_position.y = terrain_height + 1.0
		else:
			spawn_position.y = player.global_position.y + 1.0

		# Get biome at spawn position
		var biome = "valley"
		if terrain_world and terrain_world.has_method("get_biome_at"):
			biome = terrain_world.get_biome_at(Vector2(spawn_position.x, spawn_position.z))

		# Only spawn animals in appropriate biomes
		if biome not in ANIMAL_BIOMES:
			continue

		# Choose random animal type
		var animal_scene = _get_random_animal_scene(biome)

		# Check terrain collision
		if terrain_world and terrain_world.has_method("has_collision_at_position"):
			if terrain_world.has_collision_at_position(spawn_position):
				_spawn_enemy(animal_scene, spawn_position, peer_id)
				return
		else:
			_spawn_enemy(animal_scene, spawn_position, peer_id)
			return

## Get a random animal scene based on biome
func _get_random_animal_scene(biome: String) -> PackedScene:
	var animal_scenes: Array[PackedScene] = []

	# All biomes can have deer
	animal_scenes.append(DEER_SCENE)

	# Meadow and valley have more variety
	if biome in ["meadow", "valley"]:
		animal_scenes.append(PIG_SCENE)
		animal_scenes.append(SHEEP_SCENE)
	elif biome == "dark_forest":
		# Dark forest mainly has deer (less variety)
		animal_scenes.append(DEER_SCENE)  # Higher chance for deer

	return animal_scenes[randi() % animal_scenes.size()]
