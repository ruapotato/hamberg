extends Node3D

## CaveEnvironmentSpawner - Places crystal cave decorations underground
## Spawns crystals, stalactites, cave mushrooms, and lava pools in caves
## Works alongside the surface EnvironmentSpawner2D

const GRID_SIZE: float = 10.0
const SPAWN_RADIUS: float = 120.0
const UPDATE_RADIUS: float = 30.0

# Cave level depths below surface
const CAVE_LEVELS: Array[float] = [15.0, 40.0, 70.0, 100.0]

# Pool sizes
const MAX_CRYSTALS: int = 150
const MAX_STALACTITES: int = 100
const MAX_MUSHROOMS: int = 80
const MAX_LAVA: int = 40

var terrain_world: Node = null
var player: Node3D = null
var last_spawn_center: Vector3 = Vector3.ZERO
var rng := RandomNumberGenerator.new()

# Object pools
var crystal_pool: Array[Sprite3D] = []
var stalactite_pool: Array[Sprite3D] = []
var mushroom_pool: Array[Sprite3D] = []
var lava_pool: Array[MeshInstance3D] = []
var lava_damage_areas: Array[Area3D] = []

# Textures
var crystal_texture: Texture2D = null
var stalactite_texture: Texture2D = null
var mushroom_texture: Texture2D = null
var stalagmite_texture: Texture2D = null

var _initialized: bool = false

func _ready() -> void:
	# Find terrain world
	var tw_node: Node = get_tree().root.find_child("TerrainWorld", true, false)
	if tw_node:
		terrain_world = tw_node

	_load_textures()
	_create_pools()
	_initialized = true

func _load_textures() -> void:
	# Try PNG overrides first, then generate fallbacks
	var paths: Dictionary = {
		"crystal": "res://assets/textures/environment/crystal_formation.png",
		"stalactite": "res://assets/textures/environment/stalactite.png",
		"mushroom": "res://assets/textures/environment/cave_mushroom.png",
		"stalagmite": "res://assets/textures/environment/crystal_stalagmite.png",
	}

	for key in paths:
		if ResourceLoader.exists(paths[key]):
			var tex: Texture2D = load(paths[key])
			match key:
				"crystal": crystal_texture = tex
				"stalactite": stalactite_texture = tex
				"mushroom": mushroom_texture = tex
				"stalagmite": stalagmite_texture = tex

	# Generate fallbacks for missing textures
	if not crystal_texture:
		crystal_texture = _generate_crystal_fallback()
	if not stalactite_texture:
		stalactite_texture = _generate_stalactite_fallback()
	if not mushroom_texture:
		mushroom_texture = _generate_mushroom_fallback()
	if not stalagmite_texture:
		stalagmite_texture = crystal_texture  # Reuse crystal

func _create_pools() -> void:
	# Crystal formations (floor objects)
	for i in MAX_CRYSTALS:
		var sprite := Sprite3D.new()
		sprite.texture = crystal_texture
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = 0.02
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		crystal_pool.append(sprite)

	# Stalactites (ceiling objects)
	for i in MAX_STALACTITES:
		var sprite := Sprite3D.new()
		sprite.texture = stalactite_texture
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = 0.015
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		stalactite_pool.append(sprite)

	# Cave mushrooms (floor, glowing)
	for i in MAX_MUSHROOMS:
		var sprite := Sprite3D.new()
		sprite.texture = mushroom_texture
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = 0.015
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		mushroom_pool.append(sprite)

	# Lava pools (flat red-orange planes at the bottom of deep pits)
	for i in MAX_LAVA:
		var mesh_inst := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(GRID_SIZE, GRID_SIZE)
		mesh_inst.mesh = plane

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.3, 0.0, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.2, 0.0)
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_inst.material_override = mat
		mesh_inst.visible = false
		add_child(mesh_inst)
		lava_pool.append(mesh_inst)

		# Damage area for lava
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2  # Player layer
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(GRID_SIZE, 2.0, GRID_SIZE)
		shape.shape = box
		area.add_child(shape)
		area.body_entered.connect(_on_lava_body_entered)
		mesh_inst.add_child(area)
		lava_damage_areas.append(area)

	# Lava light
	var lava_light := OmniLight3D.new()
	lava_light.light_color = Color(1.0, 0.3, 0.0)
	lava_light.light_energy = 2.0
	lava_light.omni_range = 15.0
	lava_light.name = "LavaGlow"
	add_child(lava_light)

func _process(_delta: float) -> void:
	if not _initialized:
		return

	if not player or not is_instance_valid(player):
		var players: Array[Node] = get_tree().get_nodes_in_group("local_player")
		if players.size() > 0:
			player = players[0]
			_spawn_cave_objects(player.global_position)
			return
		return

	var dist: float = player.global_position.distance_to(last_spawn_center)
	if dist > UPDATE_RADIUS:
		_spawn_cave_objects(player.global_position)

	# Update lava glow position to follow player underground
	var lava_glow: OmniLight3D = get_node_or_null("LavaGlow")
	if lava_glow and player:
		lava_glow.global_position = player.global_position + Vector3(0, -5, 0)

func _spawn_cave_objects(center: Vector3) -> void:
	last_spawn_center = center

	# Hide all
	for s in crystal_pool:
		s.visible = false
	for s in stalactite_pool:
		s.visible = false
	for s in mushroom_pool:
		s.visible = false
	for m in lava_pool:
		m.visible = false

	if not terrain_world:
		return

	var biome_gen: Node = null
	if terrain_world.has_method("get_biome_generator"):
		biome_gen = terrain_world.get_biome_generator()
	if not biome_gen:
		return

	var crystal_idx: int = 0
	var stalactite_idx: int = 0
	var mushroom_idx: int = 0
	var lava_idx: int = 0

	var grid_radius: int = int(SPAWN_RADIUS / GRID_SIZE)

	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var grid_x: int = int(center.x / GRID_SIZE) + gx
			var grid_z: int = int(center.z / GRID_SIZE) + gz

			var cell_x: float = grid_x * GRID_SIZE + GRID_SIZE * 0.5
			var cell_z: float = grid_z * GRID_SIZE + GRID_SIZE * 0.5

			var dist: float = Vector2(cell_x - center.x, cell_z - center.z).length()
			if dist > SPAWN_RADIUS:
				continue

			# Deterministic seed per cell
			rng.seed = grid_x * 48271 ^ grid_z * 65537

			# Get surface height
			var surface_h: float = terrain_world.get_terrain_height_at(Vector2(cell_x, cell_z))

			# Check each cave level for objects
			for level_depth in CAVE_LEVELS:
				var cave_y: float = surface_h - level_depth

				# Sample cave carving at this position
				var cave_pos := Vector3(cell_x, cave_y, cell_z)
				if not biome_gen.has_method("get_fast_cave_carving"):
					continue

				var carving: float = biome_gen.get_fast_cave_carving(cave_pos, surface_h)
				if carving < 0.3:
					continue  # Not deep enough in cave

				# We're in a cave! Place objects based on RNG
				var roll: float = rng.randf()

				# Crystal formation on floor (30% chance)
				if roll < 0.30 and crystal_idx < MAX_CRYSTALS:
					var sprite: Sprite3D = crystal_pool[crystal_idx]
					var offset_x: float = rng.randf_range(-3.0, 3.0)
					var offset_z: float = rng.randf_range(-3.0, 3.0)
					sprite.global_position = Vector3(cell_x + offset_x, cave_y - 2.0, cell_z + offset_z)
					sprite.visible = true
					var s: float = rng.randf_range(0.8, 1.5)
					sprite.scale = Vector3(s, s, s)
					crystal_idx += 1

				# Stalactite on ceiling (25% chance)
				elif roll < 0.55 and stalactite_idx < MAX_STALACTITES:
					var sprite: Sprite3D = stalactite_pool[stalactite_idx]
					var offset_x: float = rng.randf_range(-3.0, 3.0)
					var offset_z: float = rng.randf_range(-3.0, 3.0)
					# Ceiling is roughly 5-8 units above cave center
					sprite.global_position = Vector3(cell_x + offset_x, cave_y + 4.0, cell_z + offset_z)
					sprite.visible = true
					sprite.flip_v = true  # Hang upside down
					stalactite_idx += 1

				# Glowing mushroom on floor (20% chance)
				elif roll < 0.75 and mushroom_idx < MAX_MUSHROOMS:
					var sprite: Sprite3D = mushroom_pool[mushroom_idx]
					var offset_x: float = rng.randf_range(-2.0, 2.0)
					var offset_z: float = rng.randf_range(-2.0, 2.0)
					sprite.global_position = Vector3(cell_x + offset_x, cave_y - 2.5, cell_z + offset_z)
					sprite.visible = true
					var s: float = rng.randf_range(0.6, 1.0)
					sprite.scale = Vector3(s, s, s)
					mushroom_idx += 1

			# Lava at the deepest level (below level 4)
			var deepest_y: float = surface_h - 105.0
			var deep_carving: float = biome_gen.get_fast_cave_carving(
				Vector3(cell_x, deepest_y, cell_z), surface_h)
			if deep_carving > 0.2 and lava_idx < MAX_LAVA:
				var lava_mesh: MeshInstance3D = lava_pool[lava_idx]
				lava_mesh.global_position = Vector3(cell_x, deepest_y - 3.0, cell_z)
				lava_mesh.visible = true
				lava_idx += 1

func _on_lava_body_entered(body: Node3D) -> void:
	# Kill player on lava contact
	if body.has_method("take_damage") and body.collision_layer & 2:
		print("[CaveSpawner] Player fell into lava!")
		body.take_damage(9999.0, 0, Vector3.ZERO)

func _generate_crystal_fallback() -> Texture2D:
	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Simple pink crystal shape
	for y in range(20, 120):
		var width: int = int(max(1, 20 - abs(y - 60) * 0.3))
		for x in range(32 - width, 32 + width):
			if x >= 0 and x < 64:
				var brightness: float = 0.7 + randf() * 0.3
				img.set_pixel(x, y, Color(brightness, 0.0, brightness * 0.58, 1.0))
	return ImageTexture.create_from_image(img)

func _generate_stalactite_fallback() -> Texture2D:
	var img := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Tapered triangle
	for y in range(0, 120):
		var width: int = int(max(1, y * 0.12))
		for x in range(16 - width, 16 + width):
			if x >= 0 and x < 32:
				img.set_pixel(x, y, Color(0.2, 0.2, 0.35, 1.0))
	return ImageTexture.create_from_image(img)

func _generate_mushroom_fallback() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Stem
	for y in range(35, 60):
		for x in range(28, 36):
			img.set_pixel(x, y, Color(0.3, 0.25, 0.2, 1.0))
	# Cap with green glow
	for y in range(10, 40):
		for x in range(10, 54):
			var dx: int = x - 32
			var dy: int = y - 25
			if dx * dx + dy * dy < 400:
				img.set_pixel(x, y, Color(0.0, 0.8 + randf() * 0.2, 0.42, 1.0))
	return ImageTexture.create_from_image(img)
