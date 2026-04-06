extends Node3D

## EnvironmentSpawner2D - Places billboard trees, rocks, and grass on terrain
## Client-side only visual decoration. Paper Mario style 2D objects in 3D world.

signal environment_ready()

# Configuration
@export_group("Spawning")
@export var spawn_radius: float = 200.0
@export var update_radius: float = 40.0  # Respawn when player moves this far
@export var tree_density: float = 0.025
@export var rock_density: float = 0.015
@export var bush_density: float = 0.03
@export var grass_density: float = 0.06

@export var decor_density: float = 0.04

@export_group("Object Limits")
@export var max_trees: int = 600
@export var max_rocks: int = 250
@export var max_bushes: int = 400
@export var max_grass: int = 800
@export var max_decor: int = 300
@export var max_forageables: int = 200

# Internal state
var terrain_world: Node = null
var player: Node3D = null
var last_spawn_center: Vector3 = Vector3.ZERO
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Object pools
var tree_pool: Array[StaticBody3D] = []
var bush_pool: Array[StaticBody3D] = []
var rock_pool: Array[StaticBody3D] = []
var grass_pool: Array[StaticBody3D] = []
var decor_pool: Array[Sprite3D] = []
var forageable_pool: Array[StaticBody3D] = []

# Active objects tracking
var active_trees: Dictionary = {}
var active_bushes: Dictionary = {}
var active_rocks: Dictionary = {}
var active_grass: Dictionary = {}
var active_decor: Dictionary = {}
var active_forageables: Dictionary = {}

# Destroyed object tracking (synced from server)
var destroyed_object_ids: Dictionary = {}  # tree_id/bush_id -> true

# Map from tree_id -> pool object for runtime removal
var id_to_object: Dictionary = {}  # tree_id/bush_id -> StaticBody3D

# Texture references (only front view used - trees are billboard sprites)
var tree_textures_front: Dictionary = {}
var bush_texture: ImageTexture = null
var rock_texture: ImageTexture = null
var grass_texture: ImageTexture = null
var decor_textures: Dictionary = {}  # name -> ImageTexture

# Grid-based spawning
const GRID_SIZE: float = 8.0

# Tree collision
const TREE_COLLISION_LAYER: int = 1

# Tree types by biome
const BIOME_TREES: Dictionary = {
	"valley": ["oak", "oak", "pine", "magic", "willow", "birch", "cherry_blossom"],
	"meadow": ["oak", "pine", "pine", "oak"],
	"dark_forest": ["dark_oak", "dark_oak", "swamp", "dead", "mushroom_giant", "baobab"],
	"swamp": ["swamp", "swamp", "dead", "swamp", "willow"],
	"mountain": ["frost_pine", "frost_pine", "pine", "dead", "birch"],
	"desert": ["cactus", "cactus", "palm", "dead"],
	"wizardland": ["crystal_tree", "crystal_tree", "magic", "crystal_tree", "cherry_blossom", "mushroom_giant"],
	"hell": ["ember_tree", "ember_tree", "dead", "ember_tree"],
}

# Tree density multiplier by biome
const BIOME_TREE_DENSITY: Dictionary = {
	"valley": 1.2,
	"meadow": 0.7,
	"dark_forest": 1.5,
	"swamp": 0.8,
	"mountain": 0.4,
	"desert": 0.15,
	"wizardland": 0.6,
	"hell": 0.3,
}

# Grass spawning by biome
const BIOME_HAS_GRASS: Dictionary = {
	"valley": true,
	"meadow": true,
	"dark_forest": true,
	"swamp": true,
	"mountain": false,
	"desert": false,
	"wizardland": true,
	"hell": false,
}

# Bush spawning by biome
const BIOME_HAS_BUSHES: Dictionary = {
	"valley": true,
	"meadow": true,
	"dark_forest": true,
	"swamp": true,
	"mountain": false,
	"desert": false,
	"wizardland": false,
	"hell": false,
}

# Decoration types by biome (small visual-only objects + forageables)
const BIOME_DECOR: Dictionary = {
	"valley": ["fern", "flower_blue", "flower_gold", "mushroom_small", "stump", "log", "blueberry_bush", "carrot_plant"],
	"meadow": ["flower_blue", "flower_gold", "tall_grass", "fern"],
	"dark_forest": ["mushroom_small", "fern", "log", "stump", "cattail", "shadow_mushroom", "nightshade_bush", "truffle_spot"],
	"swamp": ["cattail", "cattail", "mushroom_small", "log", "fern", "bog_root_plant", "marsh_herb_plant", "lotus_plant"],
	"mountain": ["crystal_cluster", "stump", "flower_blue", "frost_berry_bush", "alpine_herb_plant"],
	"desert": ["sage_plant"],
	"wizardland": ["crystal_cluster", "crystal_cluster", "flower_gold", "mushroom_small", "mana_fruit_tree", "arcane_herb_plant"],
	"hell": ["ember_pepper_plant", "brimstone_plant"],
}

# Forageable drops - forageables use collectible_bush_2d mechanics
const FORAGEABLE_DROPS: Dictionary = {
	"flower_blue": {"plant_fiber": 1},
	"flower_gold": {"plant_fiber": 1},
	"fern": {"plant_fiber": 2},
	"tall_grass": {"plant_fiber": 1},
	"cattail": {"plant_fiber": 1},
	"blueberry_bush": {"blueberry": 2},
	"carrot_plant": {"carrot": 1, "carrot_seed": 1},
	"shadow_mushroom": {"dark_mushroom": 2},
	"nightshade_bush": {"nightshade_berry": 1},
	"truffle_spot": {"truffle": 1},
	"bog_root_plant": {"swamp_root": 1},
	"marsh_herb_plant": {"marsh_herb": 2},
	"lotus_plant": {"lotus_seed": 1},
	"frost_berry_bush": {"frost_berry": 2},
	"alpine_herb_plant": {"alpine_herb": 1},
	"sage_plant": {"desert_sage": 1},
	"mana_fruit_tree": {"mana_fruit": 1},
	"arcane_herb_plant": {"arcane_herb": 1},
	"ember_pepper_plant": {"ember_pepper": 1},
	"brimstone_plant": {"brimstone_root": 1},
}

# Biome rock colors - Hollow Knight blue world
const BIOME_ROCK_COLORS: Dictionary = {
	"valley": Color(0.2, 0.25, 0.45),        # Blue-gray
	"meadow": Color(0.25, 0.3, 0.5),         # Light blue-gray
	"dark_forest": Color(0.1, 0.12, 0.25),   # Very dark blue
	"swamp": Color(0.12, 0.1, 0.3),          # Dark murky blue-purple
	"mountain": Color(0.5, 0.55, 0.72),      # Cool blue-gray (icy)
	"desert": Color(0.35, 0.35, 0.6),        # Muted blue-gray
	"wizardland": Color(0.2, 0.2, 0.65),     # Deep blue crystal
	"hell": Color(0.08, 0.05, 0.18),         # Near-black blue
}

# Biome grass colors - Hollow Knight blue world
const BIOME_GRASS_COLORS: Dictionary = {
	"valley": Color(0.3, 0.45, 0.9),         # Bright blue
	"meadow": Color(0.35, 0.5, 0.85),        # Light blue
	"dark_forest": Color(0.08, 0.12, 0.35),  # Deep navy
	"swamp": Color(0.2, 0.18, 0.45),         # Murky blue-purple
	"wizardland": Color(0.3, 0.3, 0.95),     # Bright vibrant blue
}


func _ready() -> void:
	print("[EnvironmentSpawner2D] Initializing...")

	# Wait a frame for other nodes to be ready
	await get_tree().process_frame

	# Find terrain world
	var terrain_nodes = get_tree().get_nodes_in_group("terrain_world")
	if terrain_nodes.size() > 0:
		terrain_world = terrain_nodes[0]
		print("[EnvironmentSpawner2D] Found terrain world")

	# Generate textures
	_generate_textures()

	# Create object pools
	_create_object_pools()

	print("[EnvironmentSpawner2D] Ready")
	emit_signal("environment_ready")


func _process(_delta: float) -> void:
	# Find player if not set
	if not player or not is_instance_valid(player):
		var players = get_tree().get_nodes_in_group("local_player")
		if players.size() > 0:
			player = players[0]
			last_spawn_center = player.global_position
			_spawn_environment_around(player.global_position)
			return
		return

	# Check if player moved far enough to respawn
	var dist_from_center = player.global_position.distance_to(last_spawn_center)
	if dist_from_center > update_radius:
		_spawn_environment_around(player.global_position)


func _generate_textures() -> void:
	var tex_gen = get_node_or_null("/root/TextureGenerator")

	if tex_gen:
		var all_tree_types := ["oak", "pine", "dead", "magic", "swamp",
							   "cactus", "palm", "frost_pine", "crystal_tree",
							   "ember_tree", "dark_oak",
							   "willow", "birch", "baobab", "cherry_blossom",
							   "mushroom_giant"]
		for tree_type in all_tree_types:
			tree_textures_front[tree_type] = tex_gen.generate_tree_texture(tree_type, "front")
		bush_texture = tex_gen.generate_bush_texture()
		print("[EnvironmentSpawner2D] Generated %d tree textures + bush texture (front only, billboard)" % all_tree_types.size())
	else:
		_generate_fallback_textures()

	_generate_rock_texture()
	_generate_grass_texture()
	_load_decor_textures()


func _generate_fallback_textures() -> void:
	var img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Trunk (dark blue bark)
	for y in range(90, 124):
		for x in range(28, 36):
			img.set_pixel(x, y, Color(0.08, 0.12, 0.30))

	# Canopy (blue shades)
	for y in range(10, 95):
		for x in range(10, 54):
			var dx = x - 32
			var dy = y - 50
			if dx * dx + dy * dy < 900:
				img.set_pixel(x, y, Color(0.15 + randf() * 0.1, 0.25 + randf() * 0.15, 0.6 + randf() * 0.2))

	var tex = ImageTexture.create_from_image(img)
	for tree_type in ["oak", "pine", "dead", "magic", "swamp",
					   "cactus", "palm", "frost_pine", "crystal_tree",
					   "ember_tree", "dark_oak",
					   "willow", "birch", "baobab", "cherry_blossom",
					   "mushroom_giant"]:
		tree_textures_front[tree_type] = tex


func _generate_rock_texture() -> void:
	# Check for user-edited PNG override
	var tex_gen = get_node_or_null("/root/TextureGenerator")
	if tex_gen:
		var override = tex_gen._check_override("rock")
		if override:
			rock_texture = override
			return

	var img = Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = 24
	var cy = 30

	for y in range(48):
		for x in range(48):
			var dx = x - cx
			var dy = (y - cy) * 1.3
			var noise_offset = sin(x * 0.5) * 3 + cos(y * 0.7) * 2
			var dist = sqrt(dx * dx + dy * dy) + noise_offset

			if dist < 20:
				var shade = 0.4 + (1.0 - dist / 20.0) * 0.3 + randf() * 0.1
				var color = Color(shade * 0.4, shade * 0.45, shade * 0.7)
				img.set_pixel(x, y, color)

	# Save for user editing
	if tex_gen:
		tex_gen._save_texture_png("rock", img)

	rock_texture = ImageTexture.create_from_image(img)


func _generate_grass_texture() -> void:
	# Check for user-edited PNG override
	var tex_gen = get_node_or_null("/root/TextureGenerator")
	if tex_gen:
		var override = tex_gen._check_override("grass")
		if override:
			grass_texture = override
			return

	var img = Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for blade in range(5):
		var bx = 6 + blade * 5 + randi() % 3
		var sway = randf() * 6 - 3

		for y in range(48):
			var progress = y / 48.0
			var x_offset = int(sway * (1.0 - progress))
			var blade_width = max(1, int(2 * (1.0 - progress)))

			for w in range(-blade_width, blade_width + 1):
				var px = bx + x_offset + w
				var py = 47 - y
				if px >= 0 and px < 32 and py >= 0 and py < 48:
					var shade = 0.3 + progress * 0.4 + randf() * 0.1
					img.set_pixel(px, py, Color(shade * 0.35, shade * 0.45, shade * 0.9))

	# Save for user editing
	if tex_gen:
		tex_gen._save_texture_png("grass", img)

	grass_texture = ImageTexture.create_from_image(img)


func _load_decor_textures() -> void:
	var decor_names := ["fern", "flower_blue", "flower_gold", "tall_grass",
						"cattail", "mushroom_small", "crystal_cluster",
						"log", "stump",
						"blueberry_bush", "carrot_plant", "shadow_mushroom",
						"nightshade_bush", "truffle_spot", "bog_root_plant",
						"marsh_herb_plant", "lotus_plant", "frost_berry_bush",
						"alpine_herb_plant", "sage_plant", "mana_fruit_tree",
						"arcane_herb_plant", "ember_pepper_plant", "brimstone_plant"]
	var env_dir := "res://assets/textures/environment/"
	# Fallback textures for forageables that don't have their own PNG
	var forageable_fallbacks: Dictionary = {}
	for dname in decor_names:
		var path: String = env_dir + dname + ".png"
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img:
				decor_textures[dname] = ImageTexture.create_from_image(img)
		elif forageable_fallbacks.has(dname) and decor_textures.has(forageable_fallbacks[dname]):
			decor_textures[dname] = decor_textures[forageable_fallbacks[dname]]
	# Second pass for fallbacks that reference textures loaded later
	for dname in forageable_fallbacks:
		if not decor_textures.has(dname):
			var fallback: String = forageable_fallbacks[dname]
			if decor_textures.has(fallback):
				decor_textures[dname] = decor_textures[fallback]
	print("[EnvironmentSpawner2D] Loaded %d decoration textures" % decor_textures.size())


func _create_object_pools() -> void:
	# Create tree pool - each tree is a StaticBody3D with collision
	for _i in range(max_trees):
		var tree = _create_tree_body()
		tree.visible = false
		add_child(tree)
		tree_pool.append(tree)

	# Create bush pool - each bush is a StaticBody3D with collision (interactable)
	for _i in range(max_bushes):
		var bush = _create_bush_body()
		bush.visible = false
		add_child(bush)
		bush_pool.append(bush)

	# Create rock pool - each rock is a StaticBody3D with collision (interactable)
	for _i in range(max_rocks):
		var rock = _create_rock_body()
		rock.visible = false
		add_child(rock)
		rock_pool.append(rock)

	# Create grass pool - each grass is a StaticBody3D with collision (collectible)
	for _i in range(max_grass):
		var grass = _create_grass_body()
		grass.visible = false
		add_child(grass)
		grass_pool.append(grass)

	# Create decoration pool (visual-only billboard sprites)
	for _i in range(max_decor):
		var sprite = _create_billboard_sprite()
		sprite.visible = false
		add_child(sprite)
		decor_pool.append(sprite)

	# Create forageable pool (collectible bushes with custom drops)
	for _i in range(max_forageables):
		var forageable = _create_forageable_body()
		forageable.visible = false
		add_child(forageable)
		forageable_pool.append(forageable)

	print("[EnvironmentSpawner2D] Created pools: %d trees, %d bushes, %d rocks, %d grass, %d decor, %d forageables" % [max_trees, max_bushes, max_rocks, max_grass, max_decor, max_forageables])


func _create_tree_body() -> StaticBody3D:
	var ChoppableTree2D = preload("res://client/choppable_tree_2d.gd")
	var body = StaticBody3D.new()
	body.set_script(ChoppableTree2D)
	body.collision_layer = TREE_COLLISION_LAYER
	body.collision_mask = 0

	# Capsule collision for trunk
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 3.0
	collision.shape = capsule
	collision.position = Vector3(0, 1.5, 0)
	body.add_child(collision)

	# Billboard Sprite3D - always faces camera on Y axis (no angle switching)
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 0
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(sprite)

	return body


func _create_bush_body() -> StaticBody3D:
	var CollectibleBush2D = preload("res://client/collectible_bush_2d.gd")
	var body = StaticBody3D.new()
	body.set_script(CollectibleBush2D)
	body.collision_layer = TREE_COLLISION_LAYER
	body.collision_mask = 0

	# Small box collision for bush
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.6)
	collision.shape = box
	collision.position = Vector3(0, 0.25, 0)
	body.add_child(collision)

	# Billboard Sprite3D
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 0
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(sprite)

	return body


func _create_rock_body() -> StaticBody3D:
	var CollectibleRock2D = preload("res://client/collectible_rock_2d.gd")
	var body = StaticBody3D.new()
	body.set_script(CollectibleRock2D)
	body.collision_layer = TREE_COLLISION_LAYER
	body.collision_mask = 0

	# Small sphere collision for rock
	var collision = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.35
	collision.shape = sphere
	collision.position = Vector3(0, 0.2, 0)
	body.add_child(collision)

	# Billboard Sprite3D
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 0
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(sprite)

	return body


func _create_billboard_sprite() -> Sprite3D:
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 0
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sprite


func _create_forageable_body() -> StaticBody3D:
	var CollectibleBush2D = preload("res://client/collectible_bush_2d.gd")
	var body = StaticBody3D.new()
	body.set_script(CollectibleBush2D)
	body.collision_layer = TREE_COLLISION_LAYER
	body.collision_mask = 0

	# Small box collision
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.5, 0.4, 0.5)
	collision.shape = box
	collision.position = Vector3(0, 0.2, 0)
	body.add_child(collision)

	# Billboard Sprite3D
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 0
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(sprite)

	return body


func _create_grass_body() -> StaticBody3D:
	var CollectibleBush2D = preload("res://client/collectible_bush_2d.gd")
	var body = StaticBody3D.new()
	body.set_script(CollectibleBush2D)
	body.collision_layer = TREE_COLLISION_LAYER
	body.collision_mask = 0

	# Small box collision for grass
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	collision.shape = box
	collision.position = Vector3(0, 0.15, 0)
	body.add_child(collision)

	# Billboard Sprite3D
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 0
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.texture = grass_texture
	body.add_child(sprite)

	return body


func _spawn_environment_around(center: Vector3) -> void:
	last_spawn_center = center

	# Clear tracking
	active_trees.clear()
	active_bushes.clear()
	active_rocks.clear()
	active_grass.clear()
	active_decor.clear()
	active_forageables.clear()
	id_to_object.clear()

	# Hide all pooled objects (skip bushes waiting to respawn)
	for obj in tree_pool:
		obj.visible = false
	for obj in bush_pool:
		if not obj.is_destroyed:
			obj.visible = false
	for obj in rock_pool:
		if not obj.is_destroyed:
			obj.visible = false
	for obj in grass_pool:
		if not obj.is_destroyed:
			obj.visible = false
	for obj in decor_pool:
		obj.visible = false
	for obj in forageable_pool:
		if not obj.is_destroyed:
			obj.visible = false

	var tree_idx = 0
	var bush_idx = 0
	var rock_idx = 0
	var grass_idx = 0
	var decor_idx = 0
	var forageable_idx = 0

	# Collect grid cells sorted by distance
	var grid_radius = int(spawn_radius / GRID_SIZE)
	var cells: Array = []

	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var grid_x = int(center.x / GRID_SIZE) + gx
			var grid_z = int(center.z / GRID_SIZE) + gz

			var cell_center = Vector3(grid_x * GRID_SIZE + GRID_SIZE * 0.5, 0, grid_z * GRID_SIZE + GRID_SIZE * 0.5)
			var dist = Vector2(cell_center.x - center.x, cell_center.z - center.z).length()
			if dist > spawn_radius:
				continue

			cells.append({"x": grid_x, "z": grid_z, "dist": dist})

	cells.sort_custom(func(a, b): return a.dist < b.dist)

	var cell_area = GRID_SIZE * GRID_SIZE

	for cell in cells:
		var grid_x: int = cell.x
		var grid_z: int = cell.z
		var dist: float = cell.dist
		var grid_key = "%d,%d" % [grid_x, grid_z]

		# Deterministic seed per cell
		rng.seed = grid_x * 73856093 ^ grid_z * 19349663

		# Get biome for this cell
		var cell_world_x = grid_x * GRID_SIZE + GRID_SIZE * 0.5
		var cell_world_z = grid_z * GRID_SIZE + GRID_SIZE * 0.5
		var biome = _get_biome_at(cell_world_x, cell_world_z)
		var biome_density_mult = BIOME_TREE_DENSITY.get(biome, 1.0)

		# Spawn trees with minimum spacing to avoid stacking
		var num_trees = int(cell_area * tree_density * biome_density_mult * (0.5 + rng.randf()))
		var cell_tree_positions: Array[Vector2] = []
		var min_tree_spacing: float = 2.5  # Minimum distance between trees in a cell
		var tree_idx_in_cell: int = 0

		for _t in range(num_trees):
			if tree_idx >= max_trees:
				break

			var local_x = rng.randf() * GRID_SIZE
			var local_z = rng.randf() * GRID_SIZE

			# Check spacing against other trees in this cell
			var too_close = false
			var candidate = Vector2(local_x, local_z)
			for existing_pos in cell_tree_positions:
				if candidate.distance_to(existing_pos) < min_tree_spacing:
					too_close = true
					break
			if too_close:
				tree_idx_in_cell += 1
				continue

			cell_tree_positions.append(candidate)
			var world_x = grid_x * GRID_SIZE + local_x
			var world_z = grid_z * GRID_SIZE + local_z

			var height = _get_terrain_height(world_x, world_z)
			if height < -10 or height > 80:
				tree_idx_in_cell += 1
				continue

			# Deterministic tree ID based on grid cell + index within cell
			var tree_id := "2dt_%d_%d_%d" % [grid_x, grid_z, tree_idx_in_cell]
			tree_idx_in_cell += 1

			# Skip trees that were destroyed (synced from server)
			if destroyed_object_ids.has(tree_id):
				continue

			var pos = Vector3(world_x, height, world_z)
			var tree_type = _get_tree_type_for_biome(biome)

			_place_tree(tree_pool[tree_idx], pos, tree_type)
			tree_pool[tree_idx].set_meta("tree_id", tree_id)
			id_to_object[tree_id] = tree_pool[tree_idx]
			active_trees[grid_key + "_t" + str(_t)] = tree_pool[tree_idx]
			tree_idx += 1

		# Spawn rocks (interactable, persistent)
		var num_rocks = int(cell_area * rock_density * (0.5 + rng.randf()))
		var rock_idx_in_cell: int = 0
		for _r in range(num_rocks):
			if rock_idx >= max_rocks:
				break

			# Skip rocks that are destroyed (already mined)
			while rock_idx < max_rocks and rock_pool[rock_idx].is_destroyed:
				rock_idx += 1
			if rock_idx >= max_rocks:
				break

			var local_x = rng.randf() * GRID_SIZE
			var local_z = rng.randf() * GRID_SIZE
			var world_x = grid_x * GRID_SIZE + local_x
			var world_z = grid_z * GRID_SIZE + local_z

			var height = _get_terrain_height(world_x, world_z)
			if height < -100:
				rock_idx_in_cell += 1
				continue

			# Deterministic rock ID based on grid cell + index within cell
			var rock_id := "2dr_%d_%d_%d" % [grid_x, grid_z, rock_idx_in_cell]
			rock_idx_in_cell += 1

			# Skip rocks that were destroyed (synced from server)
			if destroyed_object_ids.has(rock_id):
				continue

			var pos = Vector3(world_x, height, world_z)
			_place_rock(rock_pool[rock_idx], pos, biome)
			rock_pool[rock_idx].set_meta("tree_id", rock_id)
			id_to_object[rock_id] = rock_pool[rock_idx]
			active_rocks[grid_key + "_r" + str(_r)] = rock_pool[rock_idx]
			rock_idx += 1

		# Spawn bushes (interactable, only in biomes with bushes)
		if BIOME_HAS_BUSHES.get(biome, false):
			var num_bushes = int(cell_area * bush_density * (0.5 + rng.randf()))
			var bush_idx_in_cell: int = 0
			for _b in range(num_bushes):
				if bush_idx >= max_bushes:
					break

				# Skip bushes that are destroyed (waiting to respawn)
				while bush_idx < max_bushes and bush_pool[bush_idx].is_destroyed:
					bush_idx += 1
				if bush_idx >= max_bushes:
					break

				var local_x = rng.randf() * GRID_SIZE
				var local_z = rng.randf() * GRID_SIZE
				var world_x = grid_x * GRID_SIZE + local_x
				var world_z = grid_z * GRID_SIZE + local_z

				var height = _get_terrain_height(world_x, world_z)
				if height < 0 or height > 50:
					bush_idx_in_cell += 1
					continue

				# Deterministic bush ID based on grid cell + index within cell
				var bush_id := "2db_%d_%d_%d" % [grid_x, grid_z, bush_idx_in_cell]
				bush_idx_in_cell += 1

				# Skip bushes that were destroyed (synced from server)
				if destroyed_object_ids.has(bush_id):
					continue

				var pos = Vector3(world_x, height, world_z)
				_place_bush(bush_pool[bush_idx], pos, biome)
				bush_pool[bush_idx].set_meta("tree_id", bush_id)
				id_to_object[bush_id] = bush_pool[bush_idx]
				active_bushes[grid_key + "_b" + str(_b)] = bush_pool[bush_idx]
				bush_idx += 1

		# Spawn grass (only near player, only in biomes with grass)
		if dist < spawn_radius * 0.5 and BIOME_HAS_GRASS.get(biome, true):
			var num_grass = int(cell_area * grass_density * (0.5 + rng.randf()))
			var grass_idx_in_cell: int = 0
			for _g in range(num_grass):
				if grass_idx >= max_grass:
					break

				# Skip grass that is destroyed (waiting to respawn)
				while grass_idx < max_grass and grass_pool[grass_idx].is_destroyed:
					grass_idx += 1
				if grass_idx >= max_grass:
					break

				var local_x = rng.randf() * GRID_SIZE
				var local_z = rng.randf() * GRID_SIZE
				var world_x = grid_x * GRID_SIZE + local_x
				var world_z = grid_z * GRID_SIZE + local_z

				var height = _get_terrain_height(world_x, world_z)
				if height < 0 or height > 50:
					grass_idx_in_cell += 1
					continue

				# Deterministic grass ID based on grid cell + index within cell
				var grass_id := "2dg_%d_%d_%d" % [grid_x, grid_z, grass_idx_in_cell]
				grass_idx_in_cell += 1

				# Skip grass that was destroyed (synced from server)
				if destroyed_object_ids.has(grass_id):
					continue

				var pos = Vector3(world_x, height, world_z)
				_place_grass(grass_pool[grass_idx], pos, biome)
				grass_pool[grass_idx].set_meta("tree_id", grass_id)
				id_to_object[grass_id] = grass_pool[grass_idx]
				active_grass[grid_key + "_g" + str(_g)] = grass_pool[grass_idx]
				grass_idx += 1

		# Spawn decorations and forageables (near player, biome-dependent)
		var biome_decor: Array = BIOME_DECOR.get(biome, [])
		if dist < spawn_radius * 0.5 and biome_decor.size() > 0 and decor_textures.size() > 0:
			var num_decor = int(cell_area * decor_density * (0.3 + rng.randf()))
			var forageable_idx_in_cell: int = 0
			for _d in range(num_decor):
				var decor_type: String = biome_decor[rng.randi() % biome_decor.size()]
				if not decor_textures.has(decor_type):
					continue

				var is_forageable: bool = FORAGEABLE_DROPS.has(decor_type)

				# Check pool limits
				if is_forageable and forageable_idx >= max_forageables:
					continue
				if not is_forageable and decor_idx >= max_decor:
					continue

				# Skip destroyed forageables in pool
				if is_forageable:
					while forageable_idx < max_forageables and forageable_pool[forageable_idx].is_destroyed:
						forageable_idx += 1
					if forageable_idx >= max_forageables:
						continue

				var local_x = rng.randf() * GRID_SIZE
				var local_z = rng.randf() * GRID_SIZE
				var world_x = grid_x * GRID_SIZE + local_x
				var world_z = grid_z * GRID_SIZE + local_z

				var height = _get_terrain_height(world_x, world_z)
				if height < 0 or height > 50:
					if is_forageable:
						forageable_idx_in_cell += 1
					continue

				var pos = Vector3(world_x, height, world_z)

				if is_forageable:
					# Deterministic forageable ID
					var forageable_id := "2df_%d_%d_%d" % [grid_x, grid_z, forageable_idx_in_cell]
					forageable_idx_in_cell += 1

					# Skip destroyed forageables (synced from server)
					if destroyed_object_ids.has(forageable_id):
						continue

					_place_forageable(forageable_pool[forageable_idx], pos, decor_type)
					forageable_pool[forageable_idx].set_meta("tree_id", forageable_id)
					id_to_object[forageable_id] = forageable_pool[forageable_idx]
					active_forageables[grid_key + "_f" + str(_d)] = forageable_pool[forageable_idx]
					forageable_idx += 1
				else:
					_place_decor(decor_pool[decor_idx], pos, decor_type)
					active_decor[grid_key + "_d" + str(_d)] = decor_pool[decor_idx]
					decor_idx += 1

	print("[EnvironmentSpawner2D] Spawned %d trees, %d bushes, %d rocks, %d grass, %d decor, %d forageables around (%.0f, %.0f)" % [
		tree_idx, bush_idx, rock_idx, grass_idx, decor_idx, forageable_idx, center.x, center.z
	])


func _get_terrain_height(x: float, z: float) -> float:
	if terrain_world and terrain_world.has_method("get_terrain_height_at"):
		return terrain_world.get_terrain_height_at(Vector2(x, z))
	return 0.0


func _get_biome_at(x: float, z: float) -> String:
	if terrain_world and terrain_world.has_method("get_biome_at"):
		return terrain_world.get_biome_at(Vector2(x, z))
	return "valley"


func _get_tree_type_for_biome(biome: String) -> String:
	var tree_types: Array = BIOME_TREES.get(biome, BIOME_TREES["valley"])
	return tree_types[rng.randi() % tree_types.size()]


func _place_tree(tree_body: StaticBody3D, pos: Vector3, tree_type: String) -> void:
	var sprite = tree_body.get_child(1)  # Child 0 = collision, child 1 = billboard Sprite3D
	if not sprite:
		return

	# Single front texture - billboard sprite always faces camera
	var front_tex = tree_textures_front.get(tree_type, tree_textures_front.get("oak"))
	sprite.texture = front_tex

	# Textures are 256x512 — pixel_size controls world height
	sprite.pixel_size = 0.02 + rng.randf() * 0.01  # Base size for 256x512 textures

	var tex_height = front_tex.get_height() if front_tex else 256
	var world_height = tex_height * sprite.pixel_size

	# Wide scale variation for natural forest feel (tiny saplings to massive trees)
	var scale_var = 0.3 + rng.randf() * 2.2  # Range: 0.3 to 2.5
	sprite.scale = Vector3.ONE * scale_var

	# Blue-only tint: all trees get blue variation, no green or warm colors
	var blue_shift = rng.randf() * 0.15  # 0 to 0.15 blue push
	var brightness = 0.85 + rng.randf() * 0.3  # 0.85 to 1.15
	var tint = Color(1.0 - blue_shift * 0.3, 1.0 - blue_shift * 0.2, 1.0 + blue_shift) * brightness
	sprite.modulate = tint

	# Position sprite so base sits slightly INTO the ground (prevents hovering)
	sprite.position = Vector3(0, world_height * 0.42 * scale_var, 0)

	# Position body at ground level
	tree_body.position = pos
	var tree_rotation = rng.randf() * TAU
	tree_body.rotation.y = tree_rotation

	# Update collision shape based on scale and new texture size
	var collision: CollisionShape3D = tree_body.get_child(0) as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = collision.shape
		capsule.radius = 0.3 * scale_var
		capsule.height = world_height * 0.6 * scale_var
		collision.position = Vector3(0, world_height * 0.3 * scale_var, 0)

	# Reset tree health/state for pool reuse (if choppable)
	if tree_body.has_method("get_object_type"):
		tree_body.is_destroyed = false
		# Scale health and drops with size
		tree_body.max_health = 15.0 + scale_var * 25.0
		tree_body.current_health = tree_body.max_health
		# Bigger trees drop more wood
		tree_body.resource_drops = {"wood": max(1, int(2 + scale_var * 2))}
		tree_body.scale = Vector3.ONE

	tree_body.visible = true


func _place_bush(bush_body: StaticBody3D, pos: Vector3, biome: String = "valley") -> void:
	var sprite = bush_body.get_child(1)  # Child 0 = collision, child 1 = billboard Sprite3D
	if not sprite:
		return

	sprite.texture = bush_texture
	sprite.pixel_size = 0.015  # Bush textures are 128x128 now

	var scale_var = 0.5 + rng.randf() * 1.0  # Range: 0.5 to 1.5
	sprite.scale = Vector3.ONE * scale_var

	# Blue-only palette tint
	var blue_shift = rng.randf() * 0.12
	var brightness = 0.85 + rng.randf() * 0.3
	sprite.modulate = Color(1.0 - blue_shift * 0.3, 1.0 - blue_shift * 0.2, 1.0 + blue_shift) * brightness

	var tex_height = bush_texture.get_height() if bush_texture else 32
	var world_height = tex_height * sprite.pixel_size * scale_var
	sprite.position = Vector3(0, world_height * 0.35, 0)

	bush_body.position = pos
	bush_body.rotation.y = rng.randf() * TAU

	# Update collision shape based on scale
	var collision: CollisionShape3D = bush_body.get_child(0) as CollisionShape3D
	if collision and collision.shape is BoxShape3D:
		var box: BoxShape3D = collision.shape
		box.size = Vector3(0.6 * scale_var, 0.5 * scale_var, 0.6 * scale_var)
		collision.position = Vector3(0, 0.25 * scale_var, 0)

	# Reset bush state for pool reuse
	if bush_body.has_method("get_object_type"):
		bush_body.is_destroyed = false
		bush_body.current_health = bush_body.max_health
		bush_body.scale = Vector3.ONE

	bush_body.visible = true


func _place_rock(rock_body: StaticBody3D, pos: Vector3, biome: String = "valley") -> void:
	var sprite = rock_body.get_child(1)  # Child 0 = collision, child 1 = billboard Sprite3D
	if not sprite:
		return

	sprite.texture = rock_texture
	sprite.pixel_size = 0.02  # Rock textures are 96x96 now
	var scale_var = 0.3 + rng.randf() * 2.0  # Range: 0.3 to 2.3 (pebbles to boulders)
	sprite.scale = Vector3.ONE * scale_var

	# Blue-only tint for rocks
	var blue_shift = rng.randf() * 0.1
	var brightness = 0.85 + rng.randf() * 0.3
	sprite.modulate = Color(1.0 - blue_shift * 0.25, 1.0 - blue_shift * 0.15, 1.0 + blue_shift) * brightness

	var rock_height = 96.0 * sprite.pixel_size * scale_var
	sprite.position = Vector3(0, rock_height * 0.25, 0)

	rock_body.position = pos
	rock_body.rotation.y = rng.randf() * TAU

	# Update collision shape based on scale
	var collision: CollisionShape3D = rock_body.get_child(0) as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		var sphere: SphereShape3D = collision.shape
		sphere.radius = 0.35 * scale_var
		collision.position = Vector3(0, 0.2 * scale_var, 0)

	# Reset rock state for pool reuse
	if rock_body.has_method("get_object_type"):
		rock_body.is_destroyed = false
		rock_body.current_health = rock_body.max_health
		rock_body.scale = Vector3.ONE

	rock_body.visible = true


func _place_grass(grass_body: StaticBody3D, pos: Vector3, biome: String = "valley") -> void:
	var sprite = grass_body.get_child(1)  # Child 0 = collision, child 1 = billboard Sprite3D
	if not sprite:
		return

	sprite.texture = grass_texture
	sprite.pixel_size = 0.012  # Grass textures are 64x128 now
	var scale_var = 0.4 + rng.randf() * 1.2  # Range: 0.4 to 1.6
	sprite.scale = Vector3.ONE * scale_var

	# Blue-only tint for grass
	var blue_shift = rng.randf() * 0.12
	var brightness = 0.85 + rng.randf() * 0.3
	sprite.modulate = Color(1.0 - blue_shift * 0.3, 1.0 - blue_shift * 0.2, 1.0 + blue_shift) * brightness

	var grass_height = 48 * sprite.pixel_size * scale_var
	sprite.position = Vector3(0, grass_height * 0.35, 0)

	grass_body.position = pos
	grass_body.rotation.y = rng.randf() * TAU

	# Update collision shape based on scale
	var collision: CollisionShape3D = grass_body.get_child(0) as CollisionShape3D
	if collision and collision.shape is BoxShape3D:
		var box: BoxShape3D = collision.shape
		box.size = Vector3(0.3 * scale_var, 0.3 * scale_var, 0.3 * scale_var)
		collision.position = Vector3(0, 0.15 * scale_var, 0)

	# Reset grass state for pool reuse
	if grass_body.has_method("get_object_type"):
		grass_body.is_destroyed = false
		grass_body.current_health = grass_body.max_health
		grass_body.resource_drops = {"plant_fiber": 1}
		grass_body.scale = Vector3.ONE

	grass_body.visible = true


func _place_decor(sprite: Sprite3D, pos: Vector3, decor_type: String) -> void:
	var tex = decor_textures.get(decor_type)
	if not tex:
		return

	sprite.texture = tex
	sprite.pixel_size = 0.012  # Decoration textures are 128x128
	var scale_var = 0.5 + rng.randf() * 1.0  # Range: 0.5 to 1.5
	sprite.scale = Vector3.ONE * scale_var

	# Blue-only tint
	var blue_shift = rng.randf() * 0.1
	var brightness = 0.85 + rng.randf() * 0.3
	sprite.modulate = Color(1.0 - blue_shift * 0.25, 1.0 - blue_shift * 0.15, 1.0 + blue_shift) * brightness

	var tex_height = tex.get_height() if tex else 128
	var world_height = tex_height * sprite.pixel_size * scale_var
	sprite.position = pos + Vector3(0, world_height * 0.35, 0)
	sprite.rotation.y = rng.randf() * TAU
	sprite.visible = true


func _place_forageable(body: StaticBody3D, pos: Vector3, forageable_type: String) -> void:
	var sprite = body.get_child(1)  # Child 0 = collision, child 1 = billboard Sprite3D
	if not sprite:
		return

	var tex = decor_textures.get(forageable_type)
	if not tex:
		return

	sprite.texture = tex
	sprite.pixel_size = 0.012  # Same as decor textures (128x128)
	var scale_var = 0.6 + rng.randf() * 0.8  # Range: 0.6 to 1.4
	sprite.scale = Vector3.ONE * scale_var

	# Blue-only tint with slight gold hint for forageables
	var blue_shift = rng.randf() * 0.08
	var brightness = 0.9 + rng.randf() * 0.2
	sprite.modulate = Color(1.0 - blue_shift * 0.2, 1.0 - blue_shift * 0.1, 1.0 + blue_shift) * brightness

	var tex_height = tex.get_height() if tex else 128
	var world_height = tex_height * sprite.pixel_size * scale_var
	sprite.position = Vector3(0, world_height * 0.35, 0)

	body.position = pos
	body.rotation.y = rng.randf() * TAU

	# Update collision shape based on scale
	var collision: CollisionShape3D = body.get_child(0) as CollisionShape3D
	if collision and collision.shape is BoxShape3D:
		var box: BoxShape3D = collision.shape
		box.size = Vector3(0.5 * scale_var, 0.4 * scale_var, 0.5 * scale_var)
		collision.position = Vector3(0, 0.2 * scale_var, 0)

	# Reset forageable state and set custom drops
	if body.has_method("get_object_type"):
		body.is_destroyed = false
		body.current_health = body.max_health
		body.resource_drops = FORAGEABLE_DROPS.get(forageable_type, {"plant_fiber": 1})
		body.scale = Vector3.ONE

	body.visible = true


## Bulk set destroyed object IDs from server sync (called on connect)
func set_destroyed_objects(ids: Array) -> void:
	destroyed_object_ids.clear()
	for id in ids:
		destroyed_object_ids[id] = true
	print("[EnvironmentSpawner2D] Received %d destroyed object IDs from server" % ids.size())
	# Re-spawn environment to apply destroyed state
	if player and is_instance_valid(player):
		_spawn_environment_around(player.global_position)


## Mark a single object as destroyed at runtime (real-time broadcast from server)
func mark_object_destroyed(object_id: String) -> void:
	destroyed_object_ids[object_id] = true
	# If the object is currently visible, hide it
	if id_to_object.has(object_id):
		var obj = id_to_object[object_id]
		if obj and is_instance_valid(obj):
			obj.visible = false
			# Disable collision
			var col = obj.get_child(0) as CollisionShape3D
			if col:
				col.disabled = true
