extends Node

## VillageSpawner - Server-side system that generates small villages/structures
## in the world for players to discover and loot.
##
## Villages are pre-built structures made from the same buildable pieces players use.
## They spawn deterministically from the world seed so the same seed always
## produces the same village layout. Village buildings persist via the same
## placed_buildables dictionary that player-built structures use.

# ============================================================================
# CONSTANTS
# ============================================================================

const MIN_DISTANCE_BETWEEN_VILLAGES: float = 200.0
const MIN_DISTANCE_FROM_ORIGIN: float = 100.0
const VILLAGE_SPAWN_RING_MIN: float = 120.0  # Inner radius of spawn ring
const VILLAGE_SPAWN_RING_MAX: float = 800.0  # Outer radius of spawn ring
const VILLAGE_COUNT: int = 20  # Total villages to attempt spawning
const VILLAGE_ID_PREFIX: String = "village_"  # Prefix for village buildable IDs

# Biome -> allowed structure types
const BIOME_STRUCTURES: Dictionary = {
	"valley": ["small_hut", "campsite"],
	"dark_forest": ["ruins", "campsite"],
	"swamp": ["ruins"],
	"mountain": ["watchtower"],
	"desert": ["ruins", "campsite"],
}

# ============================================================================
# LOOT TABLES
# ============================================================================

# {item_name: [min_quantity, max_quantity]}
const LOOT_COMMON: Array = [
	{"item": "wood", "min": 3, "max": 8},
	{"item": "stone", "min": 2, "max": 6},
	{"item": "resin", "min": 1, "max": 4},
	{"item": "rope", "min": 1, "max": 3},
	{"item": "arrows", "min": 3, "max": 10},
]

const LOOT_UNCOMMON: Array = [
	{"item": "iron", "min": 1, "max": 3},
	{"item": "copper", "min": 1, "max": 3},
	{"item": "charcoal", "min": 2, "max": 5},
	{"item": "cooked_venison", "min": 1, "max": 2},
	{"item": "cooked_pork", "min": 1, "max": 2},
]

const LOOT_RARE: Array = [
	{"item": "fire_wand", "min": 1, "max": 1},
	{"item": "stone_sword", "min": 1, "max": 1},
	{"item": "healing_potion", "min": 1, "max": 2},
]

# ============================================================================
# STRUCTURE TEMPLATES
# ============================================================================
# Each entry: {"type": piece_name, "pos": Vector3, "rot": float}
# Positions are relative to the village origin. rot is Y rotation in radians.

# SMALL_HUT: 2x1 floor, 4 walls, door, roof, chest
var SMALL_HUT: Array = [
	# Floors
	{"type": "wooden_floor", "pos": Vector3(0, 0, 0), "rot": 0.0},
	{"type": "wooden_floor", "pos": Vector3(2, 0, 0), "rot": 0.0},
	# Walls
	{"type": "wooden_wall", "pos": Vector3(-1, 0, 0), "rot": 0.0},
	{"type": "wooden_wall", "pos": Vector3(3, 0, 0), "rot": 0.0},
	{"type": "wooden_wall", "pos": Vector3(1, 0, -1), "rot": PI / 2.0},
	{"type": "wooden_wall", "pos": Vector3(1, 0, 1), "rot": PI / 2.0},
	# Door (replaces one wall section)
	{"type": "wooden_door", "pos": Vector3(2, 0, 1), "rot": PI / 2.0},
	# Roof
	{"type": "wooden_roof_26", "pos": Vector3(0, 2, 0), "rot": 0.0},
	{"type": "wooden_roof_26", "pos": Vector3(2, 2, 0), "rot": 0.0},
	# Loot chest
	{"type": "chest", "pos": Vector3(0.5, 0.3, 0), "rot": 0.0},
	# Fireplace outside as landmark
	{"type": "fireplace", "pos": Vector3(1, 0, 3), "rot": 0.0},
]

# WATCHTOWER: elevated platform on beams with chest on top
var WATCHTOWER: Array = [
	# Base beams (4 corners)
	{"type": "wooden_beam", "pos": Vector3(-1, 0, -1), "rot": 0.0},
	{"type": "wooden_beam", "pos": Vector3(1, 0, -1), "rot": 0.0},
	{"type": "wooden_beam", "pos": Vector3(-1, 0, 1), "rot": 0.0},
	{"type": "wooden_beam", "pos": Vector3(1, 0, 1), "rot": 0.0},
	# Elevated floor
	{"type": "wooden_floor", "pos": Vector3(0, 3, 0), "rot": 0.0},
	# Walls on top (3 sides, one open for access)
	{"type": "wooden_wall", "pos": Vector3(-1, 3, 0), "rot": 0.0},
	{"type": "wooden_wall", "pos": Vector3(1, 3, 0), "rot": 0.0},
	{"type": "wooden_wall", "pos": Vector3(0, 3, -1), "rot": PI / 2.0},
	# Stairs leading up
	{"type": "wooden_stairs", "pos": Vector3(0, 0, 2), "rot": 0.0},
	# Chest on top
	{"type": "chest", "pos": Vector3(0, 3.3, 0), "rot": 0.0},
	# Fireplace at base as landmark
	{"type": "fireplace", "pos": Vector3(2, 0, 0), "rot": 0.0},
]

# CAMPSITE: fireplace + L-shape wind break + chest
var CAMPSITE: Array = [
	# L-shape walls (wind break)
	{"type": "wooden_wall", "pos": Vector3(-1, 0, 0), "rot": 0.0},
	{"type": "wooden_wall", "pos": Vector3(-1, 0, -2), "rot": 0.0},
	{"type": "wooden_wall", "pos": Vector3(0, 0, -3), "rot": PI / 2.0},
	# Fireplace (visible landmark)
	{"type": "fireplace", "pos": Vector3(0, 0, 0), "rot": 0.0},
	# Loot chest
	{"type": "chest", "pos": Vector3(0, 0.0, -1.5), "rot": 0.0},
]

# RUINS: partial walls, no roof, exposed chest (easy loot)
var RUINS: Array = [
	# Partial walls (broken building)
	{"type": "wooden_wall", "pos": Vector3(-1, 0, 0), "rot": 0.0},
	{"type": "wooden_wall", "pos": Vector3(1, 0, -1), "rot": PI / 2.0},
	{"type": "wooden_wall", "pos": Vector3(2, 0, 0), "rot": PI / 4.0},  # Fallen/angled wall
	# Exposed chest
	{"type": "chest", "pos": Vector3(0.5, 0.0, 0), "rot": 0.3},
	# Fireplace (old campfire, still burning as landmark)
	{"type": "fireplace", "pos": Vector3(0, 0, 2), "rot": 0.0},
]

# Map of template name -> template array
var TEMPLATES: Dictionary = {}

# ============================================================================
# STATE
# ============================================================================

var server_node: Node = null
var world_seed: int = 0
var spawned_village_ids: Array = []  # Array of village IDs that have been generated
var village_positions: Array = []  # Array of {id: String, pos: Vector3, template: String}

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	TEMPLATES = {
		"small_hut": SMALL_HUT,
		"watchtower": WATCHTOWER,
		"campsite": CAMPSITE,
		"ruins": RUINS,
	}
	server_node = get_parent()

## Call this after world is loaded and terrain is ready.
## Generates villages deterministically from the world seed.
## Only spawns villages that do not already exist in placed_buildables.
func initialize(p_world_seed: int) -> void:
	world_seed = p_world_seed
	print("[VillageSpawner] Initializing with seed %d" % world_seed)

	# Check which villages already exist in saved data
	var existing_village_ids: Dictionary = {}
	for net_id in server_node.placed_buildables:
		if (net_id as String).begins_with(VILLAGE_ID_PREFIX):
			# Extract village id (e.g. "village_3_wooden_wall_0" -> "village_3")
			var parts = (net_id as String).split("_")
			if parts.size() >= 2:
				var vid = parts[0] + "_" + parts[1]
				existing_village_ids[vid] = true

	# Generate village locations deterministically
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + 131071  # Offset seed so villages differ from terrain

	var placed_positions: Array = []  # Vector2 array of placed village centers
	var villages_created: int = 0
	var villages_skipped: int = 0

	for i in VILLAGE_COUNT:
		var village_id: String = VILLAGE_ID_PREFIX + str(i)

		# Generate candidate position deterministically
		var angle: float = rng.randf_range(0, TAU)
		var distance: float = rng.randf_range(VILLAGE_SPAWN_RING_MIN, VILLAGE_SPAWN_RING_MAX)
		var candidate := Vector2(cos(angle) * distance, sin(angle) * distance)

		# Check minimum distance from origin
		if candidate.length() < MIN_DISTANCE_FROM_ORIGIN:
			continue

		# Check minimum distance from other villages
		var too_close := false
		for other_pos in placed_positions:
			if candidate.distance_to(other_pos) < MIN_DISTANCE_BETWEEN_VILLAGES:
				too_close = true
				break
		if too_close:
			continue

		# Pick a template based on biome at this location
		var template_name: String = _pick_template_for_position(candidate, rng)
		if template_name.is_empty():
			continue

		placed_positions.append(candidate)

		# Check if this village already exists in saved data
		if existing_village_ids.has(village_id):
			villages_skipped += 1
			village_positions.append({
				"id": village_id,
				"pos2d": candidate,
				"template": template_name,
			})
			continue

		# Get terrain height and spawn the village
		var terrain_world = server_node.get_node_or_null("World/TerrainWorld")
		if not terrain_world:
			push_error("[VillageSpawner] No TerrainWorld found!")
			return

		var terrain_height: float = terrain_world.get_terrain_height_at(candidate)
		var origin := Vector3(candidate.x, terrain_height, candidate.y)

		# Random Y rotation for the whole village
		var village_rotation: float = rng.randf_range(0, TAU)

		_spawn_village(village_id, origin, village_rotation, template_name, rng)
		villages_created += 1

		village_positions.append({
			"id": village_id,
			"pos2d": candidate,
			"template": template_name,
		})

	print("[VillageSpawner] Generated %d new villages, %d already existed (total positions: %d)" % [
		villages_created, villages_skipped, village_positions.size()
	])

# ============================================================================
# VILLAGE GENERATION
# ============================================================================

## Pick a structure template appropriate for the biome at this position.
func _pick_template_for_position(xz_pos: Vector2, rng: RandomNumberGenerator) -> String:
	var terrain_world = server_node.get_node_or_null("World/TerrainWorld")
	if not terrain_world or not terrain_world.has_method("get_biome_at"):
		return "campsite"  # Fallback

	var biome: String = terrain_world.get_biome_at(xz_pos)
	var allowed: Array = BIOME_STRUCTURES.get(biome, [])
	if allowed.is_empty():
		return ""

	return allowed[rng.randi() % allowed.size()]

## Spawn all buildable pieces for a village and register them in placed_buildables.
func _spawn_village(village_id: String, origin: Vector3, village_rotation: float, template_name: String, rng: RandomNumberGenerator) -> void:
	var template: Array = TEMPLATES.get(template_name, [])
	if template.is_empty():
		push_error("[VillageSpawner] Unknown template: %s" % template_name)
		return

	for piece_idx in template.size():
		var piece: Dictionary = template[piece_idx]
		var piece_type: String = piece["type"]
		var local_pos: Vector3 = piece["pos"]
		var local_rot: float = piece.get("rot", 0.0)

		# Rotate the local position around Y axis by village rotation
		var rotated_pos := local_pos.rotated(Vector3.UP, village_rotation)
		var world_pos := origin + rotated_pos
		var world_rot: float = local_rot + village_rotation

		# Create a unique network ID for this piece
		var net_id: String = "%s_%s_%d" % [village_id, piece_type, piece_idx]

		# Build the buildable_data in the same format as handle_place_buildable
		var buildable_data: Dictionary = {
			"piece_name": piece_type,
			"position": [world_pos.x, world_pos.y, world_pos.z],
			"rotation_y": world_rot,
		}

		# If this is a chest, generate loot
		if piece_type == "chest":
			var chest_inv: Array = _generate_chest_loot(origin, rng)
			buildable_data["inventory"] = chest_inv

		# Register in placed_buildables so it persists and syncs to clients
		server_node.placed_buildables[net_id] = buildable_data

	print("[VillageSpawner] Spawned %s '%s' at %s (rot: %.1f)" % [
		template_name, village_id, origin, village_rotation
	])

# ============================================================================
# LOOT GENERATION
# ============================================================================

## Generate chest inventory. Loot quality scales with distance from origin.
func _generate_chest_loot(village_origin: Vector3, rng: RandomNumberGenerator) -> Array:
	var chest_inv: Array = []
	chest_inv.resize(20)
	for i in 20:
		chest_inv[i] = {"item_name": "", "quantity": 0}

	var distance_from_origin: float = Vector2(village_origin.x, village_origin.z).length()

	# Base number of loot items: 2-4 common + scaling uncommon/rare
	var common_count: int = rng.randi_range(2, 4)
	var uncommon_chance: float = clampf(distance_from_origin / 600.0, 0.1, 0.8)
	var rare_chance: float = clampf((distance_from_origin - 300.0) / 800.0, 0.0, 0.3)

	var slot_idx: int = 0

	# Common loot
	for _i in common_count:
		if slot_idx >= 20:
			break
		var loot = LOOT_COMMON[rng.randi() % LOOT_COMMON.size()]
		chest_inv[slot_idx] = {
			"item_name": loot["item"],
			"quantity": rng.randi_range(loot["min"], loot["max"]),
		}
		slot_idx += 1

	# Uncommon loot (1-2 items based on distance)
	var uncommon_rolls: int = 1 + (1 if distance_from_origin > 300.0 else 0)
	for _i in uncommon_rolls:
		if slot_idx >= 20:
			break
		if rng.randf() < uncommon_chance:
			var loot = LOOT_UNCOMMON[rng.randi() % LOOT_UNCOMMON.size()]
			chest_inv[slot_idx] = {
				"item_name": loot["item"],
				"quantity": rng.randi_range(loot["min"], loot["max"]),
			}
			slot_idx += 1

	# Rare loot (0-1 items, only far from origin)
	if rng.randf() < rare_chance:
		if slot_idx < 20:
			var loot = LOOT_RARE[rng.randi() % LOOT_RARE.size()]
			chest_inv[slot_idx] = {
				"item_name": loot["item"],
				"quantity": rng.randi_range(loot["min"], loot["max"]),
			}

	return chest_inv

# ============================================================================
# UTILITY
# ============================================================================

## Get all village positions (for minimap/world map integration)
func get_village_positions() -> Array:
	return village_positions

## Check if a position is near a village (useful for exclusion zones)
func is_near_village(xz_pos: Vector2, radius: float = 15.0) -> bool:
	for village in village_positions:
		if xz_pos.distance_to(village["pos2d"]) < radius:
			return true
	return false
