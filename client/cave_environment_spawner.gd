extends Node3D

## CaveEnvironmentSpawner - Places crystal cave decorations underground
## Scans for actual cave air pockets near the player and places objects
## on cave floors and ceilings. Works alongside the surface EnvironmentSpawner2D.

const GRID_SIZE: float = 10.0
const SPAWN_RADIUS: float = 80.0
const UPDATE_RADIUS: float = 25.0
const Y_SCAN_STEP: float = 3.0

const MAX_CRYSTALS: int = 150
const MAX_STALACTITES: int = 100
const MAX_MUSHROOMS: int = 80
const MAX_LAVA: int = 40

var terrain_world: Node = null
var player: Node3D = null
var last_spawn_center: Vector3 = Vector3.ZERO
var rng := RandomNumberGenerator.new()

var crystal_pool: Array[Sprite3D] = []
var stalactite_pool: Array[Sprite3D] = []
var mushroom_pool: Array[Sprite3D] = []
var lava_pool: Array[MeshInstance3D] = []

var crystal_texture: Texture2D = null
var stalactite_texture: Texture2D = null
var mushroom_texture: Texture2D = null

var _initialized: bool = false

func _ready() -> void:
	var tw_node: Node = get_tree().root.find_child("TerrainWorld", true, false)
	if tw_node:
		terrain_world = tw_node
	_load_textures()
	_create_pools()
	_initialized = true

func _load_textures() -> void:
	var tex_paths: Dictionary = {
		"crystal": "res://assets/textures/environment/crystal_formation.png",
		"stalactite": "res://assets/textures/environment/stalactite.png",
		"mushroom": "res://assets/textures/environment/cave_mushroom.png",
	}
	for key in tex_paths:
		if ResourceLoader.exists(tex_paths[key]):
			var tex: Texture2D = load(tex_paths[key])
			match key:
				"crystal": crystal_texture = tex
				"stalactite": stalactite_texture = tex
				"mushroom": mushroom_texture = tex
	if not crystal_texture:
		crystal_texture = _generate_crystal_fallback()
	if not stalactite_texture:
		stalactite_texture = _generate_stalactite_fallback()
	if not mushroom_texture:
		mushroom_texture = _generate_mushroom_fallback()

func _create_pools() -> void:
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

		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(GRID_SIZE, 2.0, GRID_SIZE)
		shape.shape = box
		area.add_child(shape)
		area.body_entered.connect(_on_lava_body_entered)
		mesh_inst.add_child(area)

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
	if player.global_position.distance_to(last_spawn_center) > UPDATE_RADIUS:
		_spawn_cave_objects(player.global_position)

func _spawn_cave_objects(center: Vector3) -> void:
	last_spawn_center = center

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
	var biome_gen: RefCounted = null
	if terrain_world.has_method("get_biome_generator"):
		biome_gen = terrain_world.get_biome_generator()
	if not biome_gen or not biome_gen.has_method("get_fast_cave_carving"):
		return

	var crystal_idx: int = 0
	var stalactite_idx: int = 0
	var mushroom_idx: int = 0
	var lava_idx: int = 0
	var player_y: float = center.y
	var grid_radius: int = int(SPAWN_RADIUS / GRID_SIZE)

	for gx in range(-grid_radius, grid_radius + 1):
		for gz in range(-grid_radius, grid_radius + 1):
			var grid_x: int = int(center.x / GRID_SIZE) + gx
			var grid_z: int = int(center.z / GRID_SIZE) + gz
			var cell_x: float = grid_x * GRID_SIZE + GRID_SIZE * 0.5
			var cell_z: float = grid_z * GRID_SIZE + GRID_SIZE * 0.5

			if Vector2(cell_x - center.x, cell_z - center.z).length() > SPAWN_RADIUS:
				continue

			rng.seed = grid_x * 48271 ^ grid_z * 65537
			var surface_h: float = terrain_world.get_terrain_height_at(Vector2(cell_x, cell_z))

			# Scan Y column near player to find cave air pockets
			var scan_min: float = maxf(player_y - 30.0, surface_h - 120.0)
			var scan_max: float = minf(player_y + 20.0, surface_h - 5.0)
			if scan_min >= scan_max:
				continue

			var scan_y: float = scan_min
			while scan_y < scan_max:
				var carving: float = biome_gen.get_fast_cave_carving(
					Vector3(cell_x, scan_y, cell_z), surface_h)
				if carving < 0.4:
					scan_y += Y_SCAN_STEP
					continue

				# Found cave air — find floor and ceiling
				var floor_y: float = scan_y
				for step in range(1, 10):
					if biome_gen.get_fast_cave_carving(
						Vector3(cell_x, scan_y - float(step), cell_z), surface_h) < 0.15:
						floor_y = scan_y - float(step) + 1.0
						break

				var ceil_y: float = scan_y
				for step in range(1, 10):
					if biome_gen.get_fast_cave_carving(
						Vector3(cell_x, scan_y + float(step), cell_z), surface_h) < 0.15:
						ceil_y = scan_y + float(step) - 1.0
						break

				var roll: float = rng.randf()
				var ox: float = rng.randf_range(-3.0, 3.0)
				var oz: float = rng.randf_range(-3.0, 3.0)

				if roll < 0.25 and crystal_idx < MAX_CRYSTALS:
					var sprite: Sprite3D = crystal_pool[crystal_idx]
					sprite.global_position = Vector3(cell_x + ox, floor_y, cell_z + oz)
					sprite.visible = true
					sprite.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
					crystal_idx += 1
				elif roll < 0.45 and stalactite_idx < MAX_STALACTITES:
					var sprite: Sprite3D = stalactite_pool[stalactite_idx]
					sprite.global_position = Vector3(cell_x + ox, ceil_y, cell_z + oz)
					sprite.visible = true
					sprite.flip_v = true
					stalactite_idx += 1
				elif roll < 0.60 and mushroom_idx < MAX_MUSHROOMS:
					var sprite: Sprite3D = mushroom_pool[mushroom_idx]
					sprite.global_position = Vector3(cell_x + ox, floor_y, cell_z + oz)
					sprite.visible = true
					sprite.scale = Vector3.ONE * rng.randf_range(0.6, 1.0)
					mushroom_idx += 1

				# Skip past this cave pocket
				scan_y = ceil_y + Y_SCAN_STEP
				continue

			# Lava at deep cave pockets (90+ below surface)
			var lava_y: float = surface_h - 95.0
			if lava_y > player_y - 30.0 and lava_y < player_y + 20.0:
				var lava_carving: float = biome_gen.get_fast_cave_carving(
					Vector3(cell_x, lava_y, cell_z), surface_h)
				if lava_carving > 0.3 and lava_idx < MAX_LAVA:
					var lava_floor: float = lava_y
					for step in range(1, 10):
						if biome_gen.get_fast_cave_carving(
							Vector3(cell_x, lava_y - float(step), cell_z), surface_h) < 0.1:
							lava_floor = lava_y - float(step) + 1.0
							break
					lava_pool[lava_idx].global_position = Vector3(cell_x, lava_floor, cell_z)
					lava_pool[lava_idx].visible = true
					lava_idx += 1

func _on_lava_body_entered(body: Node3D) -> void:
	if body.has_method("take_damage") and body.collision_layer & 2:
		body.take_damage(9999.0, 0, Vector3.ZERO)

func _generate_crystal_fallback() -> Texture2D:
	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(20, 120):
		var width: int = int(max(1, 20 - abs(y - 60) * 0.3))
		for x in range(32 - width, 32 + width):
			if x >= 0 and x < 64:
				img.set_pixel(x, y, Color(0.7 + randf() * 0.3, 0.0, 0.41 + randf() * 0.17, 1.0))
	return ImageTexture.create_from_image(img)

func _generate_stalactite_fallback() -> Texture2D:
	var img := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(0, 120):
		var width: int = int(max(1, y * 0.12))
		for x in range(16 - width, 16 + width):
			if x >= 0 and x < 32:
				img.set_pixel(x, y, Color(0.2, 0.2, 0.35, 1.0))
	return ImageTexture.create_from_image(img)

func _generate_mushroom_fallback() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(35, 60):
		for x in range(28, 36):
			img.set_pixel(x, y, Color(0.3, 0.25, 0.2, 1.0))
	for y in range(10, 40):
		for x in range(10, 54):
			if (x - 32) * (x - 32) + (y - 25) * (y - 25) < 400:
				img.set_pixel(x, y, Color(0.0, 0.8 + randf() * 0.2, 0.42, 1.0))
	return ImageTexture.create_from_image(img)
