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
const ZOMBIE_SCENE = preload("res://shared/enemies/zombie.tscn")

# Zombie type weights (must sum to 1.0)
# 50% walker, 25% runner, 15% brute, 7% mage, 3% exploder
const ZOMBIE_TYPE_WEIGHTS = [
	["walker", 0.50],
	["runner", 0.75],    # cumulative: 0.50 + 0.25
	["brute", 0.90],     # cumulative: 0.75 + 0.15
	["mage_zombie", 0.97], # cumulative: 0.90 + 0.07
	["exploder", 1.00],  # cumulative: 0.97 + 0.03
]

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
const ANIMAL_SPAWN_CHECK_INTERVAL: float = 4.0  # Check every 4 seconds (more frequent)
const MAX_ANIMALS_PER_PLAYER: int = 6  # More animals for a lively world
var animal_spawn_timer: float = 0.0

# Night raid parameters
const RAID_SPAWN_INTERVAL: float = 8.0  # Spawn raid wave every 8 seconds at night
const RAID_BASE_ZOMBIES: int = 3  # Base zombies per raid wave
const RAID_ZOMBIES_PER_DAY: int = 2  # Extra zombies per day survived
const RAID_SPAWN_DISTANCE: float = 30.0  # Distance from buildings to spawn raid zombies
const RAID_BUILDING_DAMAGE: float = 5.0  # Damage per hit to buildings
const RAID_ATTACK_INTERVAL: float = 2.0  # Seconds between building attacks

# Weather-affected spawning parameters
const WEATHER_SYNC_INTERVAL: float = 5.0  # Sync weather state to clients every 5 seconds
const LIGHTNING_CHECK_INTERVAL: float = 10.0  # Check for lightning strikes every 10 seconds
const LIGHTNING_DAMAGE: float = 15.0  # Small damage from lightning
const LIGHTNING_CHANCE: float = 0.3  # 30% chance per check during storms

# Base-building raid parameters
const BASE_CLUSTER_RADIUS: float = 30.0  # Units to consider buildings "clustered" as a base
const RAID_WARNING_TIME: float = 30.0  # Seconds before raid to send warning
const DUSK_HOUR: float = 18.0  # 6pm - dusk starts
const PRE_NIGHTFALL_HOUR: float = 19.0  # 1 hour before nightfall (20:00)

# Proximity-aware difficulty zones (distance from world origin)
const ZONE_SAFE_MAX: float = 100.0       # 0-100: only walkers
const ZONE_MEDIUM_MAX: float = 300.0     # 100-300: walkers + runners
const ZONE_HARD_MAX: float = 500.0       # 300-500: all types including brutes
# 500+: mage zombies and exploders too

# Tracking
var spawn_timer: float = 0.0
var dark_forest_spawn_timer: float = 0.0  # Separate faster timer for dark forest
var night_spawn_timer: float = 0.0  # Faster spawn timer for nighttime
var state_sync_timer: float = 0.0
var raid_spawn_timer: float = 0.0
var was_night_last_frame: bool = false
var current_day: int = 1
var raid_active: bool = false
var weather_sync_timer: float = 0.0
var lightning_timer: float = 0.0
var raid_warning_sent: bool = false  # Track if we already sent the raid warning this cycle
var last_base_level_per_player: Dictionary = {}  # peer_id -> last known base level (for threshold alerts)

# Day/night cycle reference
var day_night_cycle: Node = null
var weather_manager: Node = null
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

	# Find weather manager if we don't have it
	if not weather_manager:
		_find_weather_manager()

	var is_night = _is_night_time()
	var is_raining = _is_weather_raining()
	var is_foggy = _is_weather_foggy()

	# Sync weather state to clients periodically (for movement speed effects)
	weather_sync_timer += delta
	if weather_sync_timer >= WEATHER_SYNC_INTERVAL:
		weather_sync_timer = 0.0
		_sync_weather_to_clients()

	# Lightning strikes during storms
	if _is_weather_storming():
		lightning_timer += delta
		if lightning_timer >= LIGHTNING_CHECK_INTERVAL:
			lightning_timer = 0.0
			_check_lightning_strikes()

	# Update spawn timer (normal biomes)
	spawn_timer += delta

	# Weather affects spawn interval: rain/storms = 50% faster zombie spawns
	var weather_spawn_multiplier = 0.5 if is_raining else 1.0
	# Use faster spawn interval at night
	var current_spawn_interval = NIGHT_SPAWN_CHECK_INTERVAL if is_night else SPAWN_CHECK_INTERVAL
	current_spawn_interval *= weather_spawn_multiplier

	if spawn_timer >= current_spawn_interval:
		spawn_timer = 0.0
		_check_spawns(false, is_night)  # Normal biome spawns

	# Update dark forest spawn timer (faster!)
	dark_forest_spawn_timer += delta

	# Dark forest is even faster at night
	var dark_forest_interval = DARK_FOREST_SPAWN_CHECK_INTERVAL * (0.5 if is_night else 1.0)
	dark_forest_interval *= weather_spawn_multiplier
	if dark_forest_spawn_timer >= dark_forest_interval:
		dark_forest_spawn_timer = 0.0
		_check_spawns(true, is_night)  # Dark forest spawns only

	# Update animal spawn timer
	# Animals don't spawn at night - they hide!
	# Animals also hide during rain/storms
	var animals_should_hide = is_night or is_raining
	if not animals_should_hide:
		animal_spawn_timer += delta

		if animal_spawn_timer >= ANIMAL_SPAWN_CHECK_INTERVAL:
			animal_spawn_timer = 0.0
			_check_animal_spawns()

	# Night raid system (now base-level aware)
	_update_night_raid(delta, is_night)

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

	# Fog: enemies spawn much closer (surprise attacks - halved distances)
	if _is_weather_foggy():
		min_dist *= 0.5
		max_dist *= 0.5

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
		# Zombies can spawn in ALL biomes (50% chance), biome-specific enemies fill the rest
		var enemy_scene = GAHNOME_SCENE
		var enemy_type_name = "Gahnome"
		var zombie_subtype = ""

		if randf() < 0.5:
			# Spawn a zombie (all biomes) - type depends on distance from origin
			enemy_scene = ZOMBIE_SCENE
			var dist_from_origin = Vector2(spawn_position.x, spawn_position.z).length()
			zombie_subtype = _pick_zombie_type_for_distance(dist_from_origin)
			enemy_type_name = "Zombie"
		elif biome in DARK_FOREST_BIOMES:
			enemy_scene = SPORELING_SCENE
			enemy_type_name = "Sporeling"
		# else: Gahnome (default for valley/meadow)

		print("[EnemySpawner] Spawning %s%s in biome '%s' at %s" % [enemy_type_name, ("_" + zombie_subtype if zombie_subtype else ""), biome, spawn_position])

		# Check if terrain collision exists at this position
		if terrain_world and terrain_world.has_method("has_collision_at_position"):
			if terrain_world.has_collision_at_position(spawn_position):
				# Valid spawn position with collision - spawn the enemy
				_spawn_enemy(enemy_scene, spawn_position, peer_id, is_night, zombie_subtype)
				return
		else:
			# No terrain world check available, spawn anyway (fallback)
			_spawn_enemy(enemy_scene, spawn_position, peer_id, is_night, zombie_subtype)
			return

	# All attempts failed - don't spawn (terrain not loaded yet)

## Spawn an enemy at a position with assigned host client
## is_night: if true, apply night-time buffs (more damage, more health)
## zombie_subtype: if non-empty, set zombie_type on the enemy before adding to tree
func _spawn_enemy(enemy_scene: PackedScene, position: Vector3, host_peer_id: int = 0, is_night: bool = false, zombie_subtype: String = "") -> void:
	var enemy = enemy_scene.instantiate()

	# Set zombie type BEFORE adding to tree (so _ready uses correct stats)
	if zombie_subtype != "" and enemy.has_method("set_zombie_type"):
		enemy.set_zombie_type(zombie_subtype)

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
		# For zombies, include the subtype in the name sent to clients (e.g., "Zombie_walker")
		var broadcast_name = enemy_name
		if zombie_subtype != "":
			broadcast_name = "Zombie_" + zombie_subtype
		var night_str = " [NIGHT BUFFED]" if is_night and not enemy.is_in_group("animals") else ""
		print("[EnemySpawner] Spawned %s at %s (network_id=%d, host_peer=%d)%s" % [broadcast_name, position, net_id, host_peer_id, night_str])

		# Broadcast enemy spawn to all clients (include network_id AND host_peer_id in position array)
		var enemy_path = enemy_paths[enemy]
		# IMPORTANT: Use enemy_name (from exported var) not node.name (which changes at runtime)
		var enemy_type = enemy_name  # "Gahnome", "Sporeling", or "Zombie"
		var pos_array = [position.x, position.y, position.z, net_id, host_peer_id]  # Include network_id and host_peer_id
		NetworkManager.rpc_spawn_enemy.rpc(enemy_path, enemy_type, pos_array, broadcast_name)
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

## Pick a random zombie type using weighted distribution
func _pick_random_zombie_type() -> String:
	var roll = randf()
	for entry in ZOMBIE_TYPE_WEIGHTS:
		if roll <= entry[1]:
			return entry[0]
	return "walker"  # Fallback

## Spawn enemy manually at a position (for testing/debugging)
func spawn_enemy_at(position: Vector3, enemy_type: String = "gahnome") -> void:
	match enemy_type:
		"gahnome":
			_spawn_enemy(GAHNOME_SCENE, position)
		"sporeling":
			_spawn_enemy(SPORELING_SCENE, position)
		"zombie":
			_spawn_enemy(ZOMBIE_SCENE, position, 0, false, _pick_random_zombie_type())
		_:
			# Check if it's a specific zombie type like "zombie_walker"
			if enemy_type.begins_with("zombie_"):
				var subtype = enemy_type.substr(7)  # Remove "zombie_" prefix
				_spawn_enemy(ZOMBIE_SCENE, position, 0, false, subtype)
			else:
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
				if distance <= 80.0:  # Count animals in a wider radius
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

		# Use closer distance range for animals (so players see them)
		var distance = randf_range(20.0, 45.0)

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

# ============================================================================
# NIGHT RAID SYSTEM (BASE-LEVEL AWARE)
# ============================================================================

## Get the current hour from day/night cycle (0-24)
func _get_current_hour() -> float:
	if not day_night_cycle:
		return 12.0
	if "current_hour" in day_night_cycle:
		return day_night_cycle.current_hour
	return 12.0

## Count player buildings in a cluster around a position
## Returns the effective base level (workbenches count as +2)
func _get_base_level_near(position: Vector3) -> int:
	var buildings = get_tree().get_nodes_in_group("player_buildings")
	var level := 0
	for building in buildings:
		if not is_instance_valid(building):
			continue
		var dist = building.global_position.distance_to(position)
		if dist <= BASE_CLUSTER_RADIUS:
			level += 1
			# Workbenches count as +2 (1 base + 2 bonus = 3 effective)
			if building.is_in_group("workbenches"):
				level += 2
	return level

## Determine raid tier from base level:
## 0 buildings = no raids (tier 0)
## 1-3 = small raids at night only (tier 1)
## 4-7 = medium raids, start 1 hour before nightfall (tier 2)
## 8+ = large raids, can happen at dusk too (tier 3)
func _get_raid_tier(base_level: int) -> int:
	if base_level <= 0:
		return 0
	elif base_level <= 3:
		return 1
	elif base_level <= 7:
		return 2
	else:
		return 3

## Check if it's raid time based on the raid tier
func _is_raid_time(tier: int) -> bool:
	if tier <= 0:
		return false
	var hour = _get_current_hour()
	var is_night = hour < 6.0 or hour >= 20.0
	match tier:
		1:
			# Small raids: night only
			return is_night
		2:
			# Medium raids: start 1 hour before nightfall (19:00+) through night
			return is_night or hour >= PRE_NIGHTFALL_HOUR
		3:
			# Large raids: dusk (18:00+) through night
			return is_night or hour >= DUSK_HOUR
	return false

## Update night raid state - now base-level aware
func _update_night_raid(delta: float, is_night: bool) -> void:
	# Detect day transition for day counter
	if is_night and not was_night_last_frame:
		raid_warning_sent = false
		print("[EnemySpawner] Night started. Day %d" % current_day)
	elif not is_night and was_night_last_frame:
		raid_active = false
		raid_warning_sent = false
		current_day += 1
		print("[EnemySpawner] Dawn. Now day %d" % current_day)
	was_night_last_frame = is_night

	# Find player-placed buildings
	var buildings = get_tree().get_nodes_in_group("player_buildings")
	if buildings.is_empty():
		raid_active = false
		return  # No buildings to raid

	# Find the highest base level among all player clusters
	var max_base_level := 0
	var raid_center := Vector3.ZERO
	if server_node and "spawned_players" in server_node:
		for peer_id in server_node.spawned_players:
			var player = server_node.spawned_players[peer_id]
			if not player or not is_instance_valid(player):
				continue
			var base_level = _get_base_level_near(player.global_position)

			# Check if base level crossed a threshold - send notification
			var last_level = last_base_level_per_player.get(peer_id, 0)
			var last_tier = _get_raid_tier(last_level)
			var new_tier = _get_raid_tier(base_level)
			if new_tier > last_tier and new_tier >= 2:
				# Base grew past a threshold - warn the player
				var warning_msg = "Your settlement has attracted attention..."
				if new_tier >= 3:
					warning_msg = "Your fortress draws the gaze of powerful enemies..."
				NetworkManager.rpc_server_notification.rpc_id(peer_id, warning_msg, 7.0)
				print("[EnemySpawner] Base level alert for peer %d: tier %d -> %d (level %d)" % [peer_id, last_tier, new_tier, base_level])
			last_base_level_per_player[peer_id] = base_level

			if base_level > max_base_level:
				max_base_level = base_level
				raid_center = player.global_position

	var tier = _get_raid_tier(max_base_level)
	var should_raid = _is_raid_time(tier)

	# Send raid warning 30 seconds before raid time
	if not raid_active and not raid_warning_sent and tier > 0:
		var hour = _get_current_hour()
		var warning_hour := 20.0  # Default: warn before nightfall
		if tier >= 3:
			warning_hour = DUSK_HOUR
		elif tier >= 2:
			warning_hour = PRE_NIGHTFALL_HOUR

		# Check if we're in the warning window (roughly 30 game-seconds before raid)
		# Approximate: warn ~0.5 hours before raid time
		var warn_before = warning_hour - 0.5
		if hour >= warn_before and hour < warning_hour and not is_night:
			raid_warning_sent = true
			_send_raid_warning()

	if should_raid and not raid_active:
		raid_active = true
		raid_spawn_timer = 0.0
		print("[EnemySpawner] RAID STARTED! Tier %d, base level %d, day %d" % [tier, max_base_level, current_day])
	elif not should_raid and raid_active:
		raid_active = false

	if not raid_active:
		return

	# Spawn raid waves periodically - scale with tier
	raid_spawn_timer += delta
	if raid_spawn_timer >= RAID_SPAWN_INTERVAL:
		raid_spawn_timer = 0.0
		_spawn_raid_wave(buildings, tier, max_base_level)

	# Make existing raid zombies attack nearby buildings
	_update_raid_attacks(delta, buildings)

## Send raid warning to all connected players
func _send_raid_warning() -> void:
	if not server_node or not "spawned_players" in server_node:
		return
	var message = "The ground trembles... something approaches!"
	for peer_id in server_node.spawned_players:
		NetworkManager.rpc_server_notification.rpc_id(peer_id, message, 8.0)
	print("[EnemySpawner] Sent raid warning to all players")

## Spawn a wave of raid zombies near player buildings (tier-scaled)
func _spawn_raid_wave(buildings: Array[Node], tier: int, base_level: int) -> void:
	if not server_node or not "spawned_players" in server_node:
		return

	# Calculate zombie count based on tier and day
	var base_count: int
	match tier:
		1:
			base_count = RAID_BASE_ZOMBIES  # Small: 3 base
		2:
			base_count = RAID_BASE_ZOMBIES + 3  # Medium: 6 base
		3:
			base_count = RAID_BASE_ZOMBIES + 7  # Large: 10 base
		_:
			return

	var zombie_count = base_count + (current_day - 1) * RAID_ZOMBIES_PER_DAY
	# Cap based on tier
	var max_cap = 8 if tier == 1 else (15 if tier == 2 else 25)
	zombie_count = mini(zombie_count, max_cap)

	# Get terrain world for height queries
	var terrain_world = null
	if server_node and server_node.has_node("World/TerrainWorld"):
		terrain_world = server_node.get_node("World/TerrainWorld")

	# Pick a random building as the raid target
	var target_building = buildings[randi() % buildings.size()]
	if not is_instance_valid(target_building):
		return

	var target_pos = target_building.global_position

	# Find a host peer (closest player)
	var host_peer = _find_closest_player_peer(target_pos)
	if host_peer == 0:
		return

	print("[EnemySpawner] RAID WAVE (tier %d): Spawning %d zombies near building at %s" % [tier, zombie_count, target_pos])

	for i in range(zombie_count):
		# Spawn in a ring around the building
		var angle = randf() * TAU
		var dist = randf_range(RAID_SPAWN_DISTANCE * 0.8, RAID_SPAWN_DISTANCE * 1.2)
		var spawn_pos = target_pos + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

		# Get terrain height
		if terrain_world and terrain_world.has_method("get_terrain_height_at"):
			var height = terrain_world.get_terrain_height_at(Vector2(spawn_pos.x, spawn_pos.z))
			spawn_pos.y = height + 1.0
		else:
			spawn_pos.y = target_pos.y + 1.0

		# Pick zombie subtype - higher tiers get tougher enemies
		var subtype: String
		if tier >= 3:
			# Large raids: include brutes, mages, exploders
			var dist_from_origin = Vector2(target_pos.x, target_pos.z).length()
			subtype = _pick_zombie_type_for_distance(maxf(dist_from_origin, ZONE_HARD_MAX))
		elif tier >= 2:
			# Medium raids: walkers, runners, some brutes
			var dist_from_origin = Vector2(target_pos.x, target_pos.z).length()
			subtype = _pick_zombie_type_for_distance(maxf(dist_from_origin, ZONE_MEDIUM_MAX + 50.0))
		else:
			subtype = _pick_random_zombie_type()
		_spawn_enemy(ZOMBIE_SCENE, spawn_pos, host_peer, true, subtype)

## Find the closest player peer to a world position
func _find_closest_player_peer(pos: Vector3) -> int:
	if not server_node or not "spawned_players" in server_node:
		return 0

	var closest_peer: int = 0
	var closest_dist: float = INF

	for peer_id in server_node.spawned_players:
		var player = server_node.spawned_players[peer_id]
		if not player or not is_instance_valid(player):
			continue
		var d = player.global_position.distance_to(pos)
		if d < closest_dist:
			closest_dist = d
			closest_peer = peer_id

	return closest_peer

## Make raid zombies attack nearby buildings
func _update_raid_attacks(delta: float, buildings: Array[Node]) -> void:
	for enemy in spawned_enemies:
		if not enemy or not is_instance_valid(enemy):
			continue
		if enemy.is_dead:
			continue
		if not enemy.is_in_group("night_enemy"):
			continue

		# Check if this zombie is close to any building
		for building in buildings:
			if not is_instance_valid(building):
				continue
			var dist = enemy.global_position.distance_to(building.global_position)
			if dist < 3.0:
				# Zombie is in melee range of a building - deal damage
				# Use a timer stored on the enemy to rate-limit attacks
				if not "building_attack_timer" in enemy:
					enemy.set_meta("building_attack_timer", 0.0)
				var timer = enemy.get_meta("building_attack_timer", 0.0)
				timer += delta
				if timer >= RAID_ATTACK_INTERVAL:
					timer = 0.0
					# Deal damage to building
					if building.has_method("take_damage"):
						var damage = RAID_BUILDING_DAMAGE * (1.0 + (current_day - 1) * 0.2)
						building.take_damage(damage)
						print("[EnemySpawner] Raid zombie attacked %s for %.1f damage" % [building.name, damage])
				enemy.set_meta("building_attack_timer", timer)
				break  # Only attack one building at a time

# ============================================================================
# WEATHER HELPERS
# ============================================================================

## Find the WeatherManager node
func _find_weather_manager() -> void:
	var weather_managers = get_tree().get_nodes_in_group("weather_manager")
	if weather_managers.size() > 0:
		weather_manager = weather_managers[0]
		print("[EnemySpawner] Found WeatherManager")

## Check if it's currently raining or storming
func _is_weather_raining() -> bool:
	if not weather_manager:
		return false
	if weather_manager.has_method("is_raining_or_storming"):
		return weather_manager.is_raining_or_storming()
	return false

## Check if it's currently storming (heavy rain/storm/blizzard)
func _is_weather_storming() -> bool:
	if not weather_manager:
		return false
	if weather_manager.has_method("is_storming"):
		return weather_manager.is_storming()
	return false

## Check if it's currently foggy
func _is_weather_foggy() -> bool:
	if not weather_manager:
		return false
	if weather_manager.has_method("is_foggy"):
		return weather_manager.is_foggy()
	return false

## Sync weather state to all clients (for gameplay effects like movement speed)
func _sync_weather_to_clients() -> void:
	if not weather_manager:
		return
	var weather_name = weather_manager.get_weather_name() if weather_manager.has_method("get_weather_name") else "unknown"
	var is_raining = _is_weather_raining()
	var is_storming = _is_weather_storming()
	var is_foggy = _is_weather_foggy()
	NetworkManager.rpc_sync_weather_state.rpc(weather_name, is_raining, is_storming, is_foggy)

## Check for lightning strikes near players during storms
func _check_lightning_strikes() -> void:
	if not server_node or not "spawned_players" in server_node:
		return
	if randf() > LIGHTNING_CHANCE:
		return  # No strike this check

	for peer_id in server_node.spawned_players:
		var player = server_node.spawned_players[peer_id]
		if not player or not is_instance_valid(player):
			continue
		# Lightning strikes near player (5-15 units away), small damage
		var strike_dist = randf_range(5.0, 15.0)
		var strike_angle = randf() * TAU
		var strike_pos = player.global_position + Vector3(cos(strike_angle) * strike_dist, 0, sin(strike_angle) * strike_dist)

		# 10% chance lightning actually hits the player (small damage)
		if randf() < 0.1:
			NetworkManager.rpc_enemy_damage_player.rpc_id(peer_id, LIGHTNING_DAMAGE, 0, [0.0, 0.0, 0.0])
			NetworkManager.rpc_server_notification.rpc_id(peer_id, "Lightning strikes nearby!", 3.0)
			print("[EnemySpawner] Lightning struck player %d for %.0f damage!" % [peer_id, LIGHTNING_DAMAGE])

# ============================================================================
# PROXIMITY-AWARE ZOMBIE TYPE SELECTION
# ============================================================================

## Pick zombie type based on distance from world origin
## Closer to origin = safer (only walkers), further = more dangerous types
func _pick_zombie_type_for_distance(distance_from_origin: float) -> String:
	if distance_from_origin <= ZONE_SAFE_MAX:
		# Safe zone: only walkers
		return "walker"
	elif distance_from_origin <= ZONE_MEDIUM_MAX:
		# Medium zone: walkers + runners
		var roll = randf()
		if roll < 0.65:
			return "walker"
		else:
			return "runner"
	elif distance_from_origin <= ZONE_HARD_MAX:
		# Hard zone: walkers + runners + brutes
		var roll = randf()
		if roll < 0.40:
			return "walker"
		elif roll < 0.70:
			return "runner"
		else:
			return "brute"
	else:
		# Dangerous zone (500+): all types including mage zombies and exploders
		var roll = randf()
		if roll < 0.30:
			return "walker"
		elif roll < 0.55:
			return "runner"
		elif roll < 0.75:
			return "brute"
		elif roll < 0.90:
			return "mage_zombie"
		else:
			return "exploder"
