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
@export var grass_density: float = 0.06

@export_group("Object Limits")
@export var max_trees: int = 600
@export var max_rocks: int = 250
@export var max_grass: int = 800

# Internal state
var terrain_world: Node = null
var player: Node3D = null
var last_spawn_center: Vector3 = Vector3.ZERO
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Object pools
var tree_pool: Array[StaticBody3D] = []
var rock_pool: Array[Sprite3D] = []
var grass_pool: Array[Sprite3D] = []

# Active objects tracking
var active_trees: Dictionary = {}
var active_rocks: Dictionary = {}
var active_grass: Dictionary = {}

# Texture references
var tree_textures: Dictionary = {}
var rock_texture: ImageTexture = null
var grass_texture: ImageTexture = null

# Grid-based spawning
const GRID_SIZE: float = 8.0

# Tree collision
const TREE_COLLISION_LAYER: int = 1

# Tree types by biome
const BIOME_TREES: Dictionary = {
	"valley": ["oak", "oak", "pine", "magic"],
	"meadow": ["oak", "pine", "pine", "oak"],
	"dark_forest": ["dark_oak", "dark_oak", "swamp", "dead"],
	"swamp": ["swamp", "swamp", "dead", "swamp"],
	"mountain": ["frost_pine", "frost_pine", "pine", "dead"],
	"desert": ["cactus", "cactus", "palm", "dead"],
	"wizardland": ["crystal_tree", "crystal_tree", "magic", "crystal_tree"],
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

# Biome rock colors
const BIOME_ROCK_COLORS: Dictionary = {
	"valley": Color(0.6, 0.58, 0.55),
	"meadow": Color(0.65, 0.62, 0.58),
	"dark_forest": Color(0.3, 0.35, 0.3),
	"swamp": Color(0.4, 0.38, 0.32),
	"mountain": Color(0.75, 0.78, 0.82),
	"desert": Color(0.85, 0.75, 0.55),
	"wizardland": Color(0.6, 0.4, 0.7),
	"hell": Color(0.4, 0.2, 0.15),
}

# Biome grass colors
const BIOME_GRASS_COLORS: Dictionary = {
	"valley": Color(0.3, 0.6, 0.3),
	"meadow": Color(0.35, 0.65, 0.3),
	"dark_forest": Color(0.1, 0.25, 0.15),
	"swamp": Color(0.4, 0.5, 0.25),
	"wizardland": Color(0.6, 0.3, 0.7),
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
							   "ember_tree", "dark_oak"]
		for tree_type in all_tree_types:
			tree_textures[tree_type] = tex_gen.generate_tree_texture(tree_type)
		print("[EnvironmentSpawner2D] Generated %d tree textures" % all_tree_types.size())
	else:
		_generate_fallback_textures()

	_generate_rock_texture()
	_generate_grass_texture()


func _generate_fallback_textures() -> void:
	var img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Trunk
	for y in range(90, 124):
		for x in range(28, 36):
			img.set_pixel(x, y, Color(0.4, 0.3, 0.2))

	# Canopy
	for y in range(10, 95):
		for x in range(10, 54):
			var dx = x - 32
			var dy = y - 50
			if dx * dx + dy * dy < 900:
				img.set_pixel(x, y, Color(0.2 + randf() * 0.1, 0.5 + randf() * 0.2, 0.2))

	var tex = ImageTexture.create_from_image(img)
	for tree_type in ["oak", "pine", "dead", "magic", "swamp",
					   "cactus", "palm", "frost_pine", "crystal_tree",
					   "ember_tree", "dark_oak"]:
		tree_textures[tree_type] = tex


func _generate_rock_texture() -> void:
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
				var color = Color(shade * 0.6, shade * 0.58, shade * 0.55)
				img.set_pixel(x, y, color)

	rock_texture = ImageTexture.create_from_image(img)


func _generate_grass_texture() -> void:
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
					img.set_pixel(px, py, Color(shade * 0.5, shade, shade * 0.4))

	grass_texture = ImageTexture.create_from_image(img)


func _create_object_pools() -> void:
	# Create tree pool - each tree is a StaticBody3D with collision
	for _i in range(max_trees):
		var tree = _create_tree_body()
		tree.visible = false
		add_child(tree)
		tree_pool.append(tree)

	# Create rock pool
	for _i in range(max_rocks):
		var sprite = _create_billboard_sprite()
		sprite.texture = rock_texture
		sprite.pixel_size = 0.03
		sprite.visible = false
		add_child(sprite)
		rock_pool.append(sprite)

	# Create grass pool
	for _i in range(max_grass):
		var sprite = _create_billboard_sprite()
		sprite.texture = grass_texture
		sprite.pixel_size = 0.015
		sprite.visible = false
		add_child(sprite)
		grass_pool.append(sprite)

	print("[EnvironmentSpawner2D] Created pools: %d trees, %d rocks, %d grass" % [max_trees, max_rocks, max_grass])


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

	# Billboard sprite
	var sprite = _create_billboard_sprite()
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


func _spawn_environment_around(center: Vector3) -> void:
	last_spawn_center = center

	# Clear tracking
	active_trees.clear()
	active_rocks.clear()
	active_grass.clear()

	# Hide all pooled objects
	for obj in tree_pool:
		obj.visible = false
	for obj in rock_pool:
		obj.visible = false
	for obj in grass_pool:
		obj.visible = false

	var tree_idx = 0
	var rock_idx = 0
	var grass_idx = 0

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
				continue

			cell_tree_positions.append(candidate)
			var world_x = grid_x * GRID_SIZE + local_x
			var world_z = grid_z * GRID_SIZE + local_z

			var height = _get_terrain_height(world_x, world_z)
			if height < -10 or height > 80:
				continue

			var pos = Vector3(world_x, height, world_z)
			var tree_type = _get_tree_type_for_biome(biome)

			_place_tree(tree_pool[tree_idx], pos, tree_type)
			active_trees[grid_key + "_t" + str(_t)] = tree_pool[tree_idx]
			tree_idx += 1

		# Spawn rocks
		var num_rocks = int(cell_area * rock_density * (0.5 + rng.randf()))
		for _r in range(num_rocks):
			if rock_idx >= max_rocks:
				break

			var local_x = rng.randf() * GRID_SIZE
			var local_z = rng.randf() * GRID_SIZE
			var world_x = grid_x * GRID_SIZE + local_x
			var world_z = grid_z * GRID_SIZE + local_z

			var height = _get_terrain_height(world_x, world_z)
			if height < -100:
				continue

			var pos = Vector3(world_x, height, world_z)
			_place_rock(rock_pool[rock_idx], pos, biome)
			active_rocks[grid_key + "_r" + str(_r)] = rock_pool[rock_idx]
			rock_idx += 1

		# Spawn grass (only near player, only in biomes with grass)
		if dist < spawn_radius * 0.5 and BIOME_HAS_GRASS.get(biome, true):
			var num_grass = int(cell_area * grass_density * (0.5 + rng.randf()))
			for _g in range(num_grass):
				if grass_idx >= max_grass:
					break

				var local_x = rng.randf() * GRID_SIZE
				var local_z = rng.randf() * GRID_SIZE
				var world_x = grid_x * GRID_SIZE + local_x
				var world_z = grid_z * GRID_SIZE + local_z

				var height = _get_terrain_height(world_x, world_z)
				if height < 0 or height > 50:
					continue

				var pos = Vector3(world_x, height, world_z)
				_place_grass(grass_pool[grass_idx], pos, biome)
				active_grass[grid_key + "_g" + str(_g)] = grass_pool[grass_idx]
				grass_idx += 1

	print("[EnvironmentSpawner2D] Spawned %d trees, %d rocks, %d grass around (%.0f, %.0f)" % [
		tree_idx, rock_idx, grass_idx, center.x, center.z
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
	var sprite: Sprite3D = tree_body.get_child(1) as Sprite3D  # Child 0 = collision, child 1 = sprite
	if not sprite:
		return

	sprite.texture = tree_textures.get(tree_type, tree_textures.get("oak"))
	sprite.pixel_size = 0.04 + rng.randf() * 0.02

	var tex_height = sprite.texture.get_height() if sprite.texture else 128
	var world_height = tex_height * sprite.pixel_size

	# Scale variation (wide range for natural variety: small shrubs to large trees)
	var scale_var = 0.6 + rng.randf() * 1.4  # Range: 0.6 to 2.0
	sprite.scale = Vector3.ONE * scale_var

	# Random tint variation per tree (slightly different greens/browns)
	var hue_shift = rng.randf() * 0.08 - 0.04  # -0.04 to +0.04 hue shift
	var brightness_shift = rng.randf() * 0.3 - 0.15  # -0.15 to +0.15 brightness
	var tint = Color(1.0 + hue_shift, 1.0 + brightness_shift * 0.5, 1.0 - hue_shift)
	tint = tint.lightened(brightness_shift * 0.5)
	sprite.modulate = tint

	# Position sprite so base sits on ground
	sprite.position = Vector3(0, world_height * 0.48 * scale_var, 0)

	# Position body at ground level
	tree_body.position = pos
	tree_body.rotation.y = rng.randf() * TAU

	# Update collision shape based on scale
	var collision: CollisionShape3D = tree_body.get_child(0) as CollisionShape3D
	if collision and collision.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = collision.shape
		capsule.radius = 0.4 * scale_var
		capsule.height = 3.0 * scale_var
		collision.position = Vector3(0, 1.5 * scale_var, 0)

	# Reset tree health/state for pool reuse (if choppable)
	if tree_body.has_method("get_object_type"):
		tree_body.is_destroyed = false
		# Bigger trees have more health
		tree_body.max_health = 60.0 + scale_var * 40.0
		tree_body.current_health = tree_body.max_health
		# Bigger trees drop more wood
		tree_body.resource_drops = {"wood": max(1, int(2 + scale_var * 2))}
		tree_body.scale = Vector3.ONE

	tree_body.visible = true


func _place_rock(sprite: Sprite3D, pos: Vector3, biome: String = "valley") -> void:
	sprite.pixel_size = 0.04
	var scale_var = 0.3 + rng.randf() * 1.7  # Range: 0.3 to 2.0 (wider variety)
	sprite.scale = Vector3.ONE * scale_var

	# Tint based on biome with per-rock color variation
	var rock_color: Color = BIOME_ROCK_COLORS.get(biome, BIOME_ROCK_COLORS["valley"])
	var color_shift = rng.randf() * 0.3 - 0.15  # -0.15 to +0.15
	var warm_shift = rng.randf() * 0.1 - 0.05  # Slight warm/cool variation
	rock_color = rock_color.lightened(color_shift)
	rock_color.r += warm_shift
	rock_color.b -= warm_shift
	sprite.modulate = rock_color

	var rock_height = 48 * sprite.pixel_size * scale_var
	sprite.position = pos + Vector3(0, rock_height * 0.25, 0)
	sprite.rotation.y = rng.randf() * TAU
	sprite.visible = true


func _place_grass(sprite: Sprite3D, pos: Vector3, biome: String = "valley") -> void:
	sprite.pixel_size = 0.02
	var scale_var = 0.7 + rng.randf() * 0.9
	sprite.scale = Vector3.ONE * scale_var

	# Tint based on biome
	var grass_color: Color = BIOME_GRASS_COLORS.get(biome, BIOME_GRASS_COLORS["valley"])
	sprite.modulate = grass_color.lightened(rng.randf() * 0.3 - 0.15)

	var grass_height = 48 * sprite.pixel_size * scale_var
	sprite.position = pos + Vector3(0, grass_height * 0.35, 0)
	sprite.rotation.y = rng.randf() * TAU
	sprite.visible = true
