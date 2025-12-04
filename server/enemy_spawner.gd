extends Node

## EnemySpawner - Server-side enemy spawning system
## Spawns enemies naturally around players
## CLIENT-HOST MODEL:
## - One client is designated as "host" for each enemy
## - Host client runs full AI/physics using their terrain collision
## - Host sends position reports to server at 10Hz
## - Server relays host position to all other clients
## - Server handles health/damage (authoritative)

# Spawn parameters (default/valley)
const SPAWN_CHECK_INTERVAL: float = 10.0  # Check for spawns every 10 seconds
const MIN_SPAWN_DISTANCE: float = 40.0    # Minimum distance from player (far away)
const MAX_SPAWN_DISTANCE: float = 60.0    # Maximum distance from player (far away)
const MAX_ENEMIES_PER_PLAYER: int = 3     # Max enemies per player in the area
const BEHIND_PLAYER_BIAS: float = 0.7     # 70% chance to spawn behind player

# Dark forest spawn parameters (closer and more frequent!)
const DARK_FOREST_SPAWN_CHECK_INTERVAL: float = 5.0  # Faster spawns in the dark forest
const DARK_FOREST_MIN_SPAWN_DISTANCE: float = 15.0   # Much closer (dense forest)
const DARK_FOREST_MAX_SPAWN_DISTANCE: float = 30.0   # Still relatively close
const DARK_FOREST_MAX_ENEMIES_PER_PLAYER: int = 6    # More enemies in the creepy forest

# Night-time spawn parameters (more dangerous!)
const NIGHT_SPAWN_CHECK_INTERVAL: float = 5.0   # Faster spawns at night
const NIGHT_MAX_ENEMIES_MULTIPLIER: float = 2.0 # Double max enemies at night
const NIGHT_ENEMY_DAMAGE_MULTIPLIER: float = 1.5  # 50% more damage at night
const NIGHT_ENEMY_HEALTH_MULTIPLIER: float = 1.3  # 30% more health at night
const NIGHT_MIN_SPAWN_DISTANCE: float = 25.0    # Closer spawns at night
const NIGHT_MAX_SPAWN_DISTANCE: float = 45.0    # Closer max distance at night

# State sync parameters
# PERFORMANCE: Reduced from 10Hz to 5Hz (0.1 -> 0.2) for better network performance
const STATE_SYNC_INTERVAL: float = 0.2   # 5Hz position relay

# Enemy scenes
const GAHNOME_SCENE = preload("res://shared/enemies/gahnome.tscn")
const SPORELING_SCENE = preload("res://shared/enemies/sporeling.tscn")

# Animal scenes
const DEER_SCENE = preload("res://shared/animals/deer.tscn")
const PIG_SCENE = preload("res://shared/animals/pig.tscn")
const SHEEP_SCENE = preload("res://shared/animals/sheep.tscn")

# Boss scenes
const CYCLOPS_SCENE = preload("res://shared/enemies/bosses/cyclops.tscn")

# Biome-specific enemy types
const DARK_FOREST_BIOMES = ["dark_forest"]

# Biomes where animals can spawn
const ANIMAL_BIOMES = ["meadow", "valley", "dark_forest"]

# Animal spawn parameters (separate from enemies)
const ANIMAL_SPAWN_CHECK_INTERVAL: float = 8.0  # Check every 8 seconds
const MAX_ANIMALS_PER_PLAYER: int = 3  # More animals for fun
var animal_spawn_timer: float = 0.0

# Tracking
var spawn_timer: float = 0.0
var dark_forest_spawn_timer: float = 0.0  # Separate faster timer for dark forest
var night_spawn_timer: float = 0.0  # Faster spawn timer for nighttime
var state_sync_timer: float = 0.0

# Day/night cycle reference
var day_night_cycle: Node = null
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

	# Find day/night cycle if we don't have it
	if not day_night_cycle:
		_find_day_night_cycle()

	var is_night = _is_night_time()

	# Update spawn timer (normal biomes)
	spawn_timer += delta

	# Use faster spawn interval at night
	var current_spawn_interval = NIGHT_SPAWN_CHECK_INTERVAL if is_night else SPAWN_CHECK_INTERVAL

	if spawn_timer >= current_spawn_interval:
		spawn_timer = 0.0
		_check_spawns(false, is_night)  # Normal biome spawns

	# Update dark forest spawn timer (faster!)
	dark_forest_spawn_timer += delta

	# Dark forest is even faster at night
	var dark_forest_interval = DARK_FOREST_SPAWN_CHECK_INTERVAL * (0.5 if is_night else 1.0)
	if dark_forest_spawn_timer >= dark_forest_interval:
		dark_forest_spawn_timer = 0.0
		_check_spawns(true, is_night)  # Dark forest spawns only

	# Update animal spawn timer (animals don't spawn at night - they hide!)
	if not is_night:
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
## dark_forest_only: if true, only spawn for players in dark_forest biome
## is_night: if true, use night-time spawn parameters (more enemies, closer)
func _check_spawns(dark_forest_only: bool = false, is_night: bool = false) -> void:
	if not server_node or not "spawned_players" in server_node:
		return

	# Get terrain world for biome detection
	var terrain_world = null
	if server_node and server_node.has_node("World/TerrainWorld"):
		terrain_world = server_node.get_node("World/TerrainWorld")

	var players = server_node.spawned_players

	# For each player, check if we need to spawn enemies
	for peer_id in players:
		var player = players[peer_id]
		if not player or not is_instance_valid(player):
			continue

		# Check biome at player position
		var player_biome = "valley"
		if terrain_world and terrain_world.has_method("get_biome_at"):
			player_biome = terrain_world.get_biome_at(Vector2(player.global_position.x, player.global_position.z))

		var is_in_dark_forest = player_biome in DARK_FOREST_BIOMES

		# Skip if this check doesn't match the biome requirement
		if dark_forest_only and not is_in_dark_forest:
			continue  # Dark forest timer, but player not in dark forest
		if not dark_forest_only and is_in_dark_forest:
			continue  # Normal timer, but player in dark forest (handled by dark forest timer)

		# Use different max enemies based on biome and time of day
		var max_enemies = DARK_FOREST_MAX_ENEMIES_PER_PLAYER if is_in_dark_forest else MAX_ENEMIES_PER_PLAYER
		var count_distance = DARK_FOREST_MAX_SPAWN_DISTANCE if is_in_dark_forest else MAX_SPAWN_DISTANCE

		# Night-time multiplier for more enemies
		if is_night:
			max_enemies = int(max_enemies * NIGHT_MAX_ENEMIES_MULTIPLIER)
			count_distance = NIGHT_MAX_SPAWN_DISTANCE if not is_in_dark_forest else count_distance

		# Count enemies near this player (using biome-appropriate distance)
		var nearby_enemies = _count_nearby_enemies(player.global_position, count_distance)

		# Spawn enemies if below threshold
		if nearby_enemies < max_enemies:
			var enemies_to_spawn = max_enemies - nearby_enemies
			for i in range(enemies_to_spawn):
				# The player that triggered the spawn becomes the host
				_spawn_enemy_near_player(player, peer_id, is_in_dark_forest, is_night)

## Count enemies near a position (within max_distance)
func _count_nearby_enemies(position: Vector3, max_distance: float = MAX_SPAWN_DISTANCE) -> int:
	var count = 0
	for enemy in spawned_enemies:
		if enemy and is_instance_valid(enemy):
			var distance = enemy.global_position.distance_to(position)
			if distance <= max_distance:
				count += 1
	return count

## Spawn an enemy near a player (player becomes the host for this enemy)
## is_dark_forest: if true, use closer spawn distances
## is_night: if true, use night-time spawn distances and apply night buffs
func _spawn_enemy_near_player(player: Node, peer_id: int = 0, is_dark_forest: bool = false, is_night: bool = false) -> void:
	# Validate and fix spawn position
	# Don't spawn if player Y is invalid (fell through world or died)
	if player.global_position.y < -50 or player.global_position.y > 500:
		return  # Skip spawning for invalid player positions

	# Get terrain world to check for collision
	var terrain_world = null
	if server_node and server_node.has_node("World/TerrainWorld"):
		terrain_world = server_node.get_node("World/TerrainWorld")

	# Get player's backward direction angle (opposite of where they're looking)
	var player_backward_angle = player.rotation.y  # Behind player (+Z direction in local space)

	# Use biome-specific spawn distances (night brings enemies closer!)
	var min_dist: float
	var max_dist: float
	if is_dark_forest:
		min_dist = DARK_FOREST_MIN_SPAWN_DISTANCE
		max_dist = DARK_FOREST_MAX_SPAWN_DISTANCE
	elif is_night:
		min_dist = NIGHT_MIN_SPAWN_DISTANCE
		max_dist = NIGHT_MAX_SPAWN_DISTANCE
	else:
		min_dist = MIN_SPAWN_DISTANCE
		max_dist = MAX_SPAWN_DISTANCE

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

		# Use biome-appropriate distance range
		var distance = randf_range(min_dist, max_dist)

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
		var enemy_type_name = "Gahnome"
		if biome in DARK_FOREST_BIOMES:
			enemy_scene = SPORELING_SCENE
			enemy_type_name = "Sporeling"
		print("[EnemySpawner] Spawning %s in biome '%s' at %s" % [enemy_type_name, biome, spawn_position])

		# Check if terrain collision exists at this position
		if terrain_world and terrain_world.has_method("has_collision_at_position"):
			if terrain_world.has_collision_at_position(spawn_position):
				# Valid spawn position with collision - spawn the enemy
				_spawn_enemy(enemy_scene, spawn_position, peer_id, is_night)
				return
		else:
			# No terrain world check available, spawn anyway (fallback)
			_spawn_enemy(enemy_scene, spawn_position, peer_id, is_night)
			return

	# All attempts failed - don't spawn (terrain not loaded yet)

## Spawn an enemy at a position with assigned host client
## is_night: if true, apply night-time buffs (more damage, more health)
func _spawn_enemy(enemy_scene: PackedScene, position: Vector3, host_peer_id: int = 0, is_night: bool = false) -> void:
	var enemy = enemy_scene.instantiate()

	# Assign network ID BEFORE adding to tree (so it's available in _ready)
	var net_id = next_network_id
	next_network_id += 1
	if "network_id" in enemy:
		enemy.network_id = net_id

	# Assign host peer ID
	if "host_peer_id" in enemy:
		enemy.host_peer_id = host_peer_id

	# Apply night-time buffs (enemies are stronger at night!)
	if is_night and not enemy.is_in_group("animals"):
		if "max_health" in enemy:
			enemy.max_health = int(enemy.max_health * NIGHT_ENEMY_HEALTH_MULTIPLIER)
		if "health" in enemy:
			enemy.health = int(enemy.health * NIGHT_ENEMY_HEALTH_MULTIPLIER)
		if "rock_damage" in enemy:
			enemy.rock_damage = enemy.rock_damage * NIGHT_ENEMY_DAMAGE_MULTIPLIER
		# Mark as night enemy for potential visual effects later
		enemy.add_to_group("night_enemy")

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
		var night_str = " [NIGHT BUFFED]" if is_night and not enemy.is_in_group("animals") else ""
		print("[EnemySpawner] Spawned %s at %s (network_id=%d, host_peer=%d)%s" % [enemy_name, position, net_id, host_peer_id, night_str])

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
	_remove_enemy(enemy)

## Despawn an enemy (e.g., when host disconnects and no other players available)
func despawn_enemy(enemy: Node) -> void:
	if not enemy or not is_instance_valid(enemy):
		return
	print("[EnemySpawner] Despawning enemy: %s" % enemy.name)
	_remove_enemy(enemy)
	enemy.queue_free()

## Internal: Remove enemy from tracking and notify clients
func _remove_enemy(enemy: Node) -> void:
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

## Spawn a boss at a position near a player
## Returns the spawned boss or null if spawn failed
func spawn_boss(boss_type: String, position: Vector3, host_peer_id: int = 0) -> Node:
	var boss_scene: PackedScene = null

	match boss_type:
		"cyclops":
			boss_scene = CYCLOPS_SCENE
		_:
			print("[EnemySpawner] Unknown boss type: %s" % boss_type)
			return null

	if not boss_scene:
		return null

	var boss = boss_scene.instantiate()

	# Assign network ID BEFORE adding to tree
	var net_id = next_network_id
	next_network_id += 1
	if "network_id" in boss:
		boss.network_id = net_id

	# Assign host peer ID
	if "host_peer_id" in boss:
		boss.host_peer_id = host_peer_id

	# Mark as boss
	boss.add_to_group("bosses")

	# Add to world container
	if server_node and server_node.has_node("World"):
		var world_container = server_node.get_node("World")
		world_container.add_child(boss)

		# Set position
		boss.global_position = position

		# Update spawn references
		if "spawn_y" in boss:
			boss.spawn_y = position.y
		if "last_valid_position" in boss:
			boss.last_valid_position = position

		# Track boss
		spawned_enemies.append(boss)
		enemy_paths[boss] = boss.get_path()
		enemy_network_ids[boss] = net_id
		network_id_to_enemy[net_id] = boss
		enemy_host_peers[net_id] = host_peer_id
		host_position_reports[net_id] = {}

		# Connect death signal
		if boss.has_signal("died"):
			boss.died.connect(_on_enemy_died)
		if boss.has_signal("boss_defeated"):
			boss.boss_defeated.connect(_on_boss_defeated)

		var boss_name = boss.boss_name if "boss_name" in boss else "Boss"
		print("[EnemySpawner] BOSS SPAWNED: %s at %s (network_id=%d, host_peer=%d)" % [boss_name, position, net_id, host_peer_id])

		# Broadcast boss spawn to all clients
		var boss_path = enemy_paths[boss]
		var boss_type_name = boss_name
		var pos_array = [position.x, position.y, position.z, net_id, host_peer_id]
		NetworkManager.rpc_spawn_enemy.rpc(boss_path, boss_type_name, pos_array, boss_name)

		return boss
	else:
		print("[EnemySpawner] ERROR: WorldContainer not found!")
		boss.queue_free()
		return null

## Handle boss defeat
func _on_boss_defeated(boss: Node) -> void:
	var boss_name = boss.boss_name if "boss_name" in boss else "Boss"
	print("[EnemySpawner] BOSS DEFEATED: %s" % boss_name)
	# Boss handles its own loot drops and cleanup

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
	print("[EnemySpawner] Checking animal spawns for %d players" % players.size())

	# For each player, check if we need to spawn animals
	for peer_id in players:
		var player = players[peer_id]
		if not player or not is_instance_valid(player):
			continue

		# Count animals near this player
		var nearby_animals = _count_nearby_animals(player.global_position)
		print("[EnemySpawner] Player %d has %d/%d nearby animals" % [peer_id, nearby_animals, MAX_ANIMALS_PER_PLAYER])

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
		print("[EnemySpawner] Animal spawn skipped - invalid player Y: %.1f" % player.global_position.y)
		return

	# Get terrain world
	var terrain_world = null
	if server_node and server_node.has_node("World/TerrainWorld"):
		terrain_world = server_node.get_node("World/TerrainWorld")

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
			print("[EnemySpawner] Animal spawn attempt %d: biome '%s' not in ANIMAL_BIOMES" % [attempt, biome])
			continue

		# Choose random animal type
		var animal_scene = _get_random_animal_scene(biome)
		var scene_name = "Unknown"
		if animal_scene == DEER_SCENE:
			scene_name = "Deer"
		elif animal_scene == PIG_SCENE:
			scene_name = "Flying Pig"
		elif animal_scene == SHEEP_SCENE:
			scene_name = "Unicorn Sheep"

		# Check terrain collision
		if terrain_world and terrain_world.has_method("has_collision_at_position"):
			if terrain_world.has_collision_at_position(spawn_position):
				print("[EnemySpawner] Spawning %s in biome '%s' at %s" % [scene_name, biome, spawn_position])
				_spawn_enemy(animal_scene, spawn_position, peer_id)
				return
			else:
				print("[EnemySpawner] Animal spawn attempt %d: no terrain collision at %s" % [attempt, spawn_position])
		else:
			print("[EnemySpawner] Spawning %s (no collision check) at %s" % [scene_name, spawn_position])
			_spawn_enemy(animal_scene, spawn_position, peer_id)
			return

	print("[EnemySpawner] Animal spawn failed after 5 attempts")

## Get a random animal scene based on biome
func _get_random_animal_scene(biome: String) -> PackedScene:
	var animal_scenes: Array[PackedScene] = []

	# All animal biomes can have all animals (deer, pigs, sheep)
	animal_scenes.append(DEER_SCENE)
	animal_scenes.append(PIG_SCENE)
	animal_scenes.append(SHEEP_SCENE)

	return animal_scenes[randi() % animal_scenes.size()]

# ============================================================================
# DAY/NIGHT CYCLE HELPERS
# ============================================================================

## Find the day/night cycle node in the world
func _find_day_night_cycle() -> void:
	# Try to find via terrain world group
	var terrain_worlds = get_tree().get_nodes_in_group("terrain_world")
	if terrain_worlds.size() > 0:
		var terrain_world = terrain_worlds[0]
		if terrain_world.has_node("DayNightCycle"):
			day_night_cycle = terrain_world.get_node("DayNightCycle")
			print("[EnemySpawner] Found DayNightCycle node")
			return

	# Fallback: try direct path from server
	if server_node and server_node.has_node("World/TerrainWorld/DayNightCycle"):
		day_night_cycle = server_node.get_node("World/TerrainWorld/DayNightCycle")
		print("[EnemySpawner] Found DayNightCycle via server path")

## Check if it's currently night time
func _is_night_time() -> bool:
	if not day_night_cycle:
		return false
	if day_night_cycle.has_method("is_night"):
		return day_night_cycle.is_night()
	# Fallback: check current_hour directly
	if "current_hour" in day_night_cycle:
		var hour = day_night_cycle.current_hour
		return hour < 6.0 or hour >= 20.0  # Night is 8pm to 6am
	return false
