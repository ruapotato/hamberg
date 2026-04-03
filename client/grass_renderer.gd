extends Node3D

## Client-side grass renderer using a SINGLE MultiMeshInstance3D
## Places grass instances in a radius around the local player for minimal draw calls
## All grass renders in 1-2 draw calls total regardless of world size

var terrain_world: Node3D
var is_initialized: bool = false
var world_seed: int = 0

# The single MultiMeshInstance3D for all grass
var grass_mmi: MultiMeshInstance3D
var grass_multimesh: MultiMesh

# Tracking
var last_player_pos: Vector3 = Vector3.ZERO
var needs_rebuild: bool = false
var rebuild_timer: float = 0.0

const GRASS_RADIUS := 20.0  # Radius around player to spawn grass
const GRASS_COUNT := 1500  # Total grass instances (single draw call)
const REBUILD_INTERVAL := 0.5  # How often to check if rebuild needed (seconds)
const REBUILD_DISTANCE := 5.0  # Player must move this far to trigger rebuild

func initialize(terrain_ref: Node3D, seed_value: int) -> void:
	terrain_world = terrain_ref
	world_seed = seed_value
	_create_grass_multimesh()
	is_initialized = true

func _create_grass_multimesh() -> void:
	# Create the mesh - two crossed quads (X pattern) in a single mesh
	var mesh := _create_grass_blade_mesh()

	# Create shader material
	var grass_shader = load("res://shared/environmental/grass_material.gdshader")
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = grass_shader

	# Create MultiMesh
	grass_multimesh = MultiMesh.new()
	grass_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	grass_multimesh.mesh = mesh
	grass_multimesh.instance_count = GRASS_COUNT

	# Create MultiMeshInstance3D - just ONE for all grass
	grass_mmi = MultiMeshInstance3D.new()
	grass_mmi.multimesh = grass_multimesh
	grass_mmi.material_override = grass_mat
	grass_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	grass_mmi.name = "GrassMultiMesh"
	add_child(grass_mmi)

	# Initialize all instances to zero (hidden)
	for i in GRASS_COUNT:
		grass_multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

func _create_grass_blade_mesh() -> Mesh:
	# Build two crossed quads manually using SurfaceTool for a single mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w := 0.1
	var height := 0.4

	# Quad 1: along X axis, standing upright
	_add_quad(st, Vector3(-half_w, 0, 0), Vector3(half_w, 0, 0),
		Vector3(half_w, height, 0), Vector3(-half_w, height, 0))

	# Quad 2: along Z axis, standing upright (90° crossed)
	_add_quad(st, Vector3(0, 0, -half_w), Vector3(0, 0, half_w),
		Vector3(0, height, half_w), Vector3(0, height, -half_w))

	st.generate_normals()
	return st.commit()

func _add_quad(st: SurfaceTool, bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3) -> void:
	# Single face - cull_disabled in shader handles back side
	# UV.y = 0 at base (ground), UV.y = 1 at tip (top)
	st.set_uv(Vector2(0, 0))  # bottom-left (base)
	st.add_vertex(bl)
	st.set_uv(Vector2(1, 0))  # bottom-right (base)
	st.add_vertex(br)
	st.set_uv(Vector2(1, 1))  # top-right (tip)
	st.add_vertex(tr)

	st.set_uv(Vector2(0, 0))  # bottom-left (base)
	st.add_vertex(bl)
	st.set_uv(Vector2(1, 1))  # top-right (tip)
	st.add_vertex(tr)
	st.set_uv(Vector2(0, 1))  # top-left (tip)
	st.add_vertex(tl)

func _process(delta: float) -> void:
	if not is_initialized or not terrain_world:
		return

	rebuild_timer += delta
	if rebuild_timer < REBUILD_INTERVAL:
		return
	rebuild_timer = 0.0

	# Find local player
	var player = _get_local_player()
	if not player:
		return

	var player_pos: Vector3 = player.global_position
	if last_player_pos.distance_to(player_pos) > REBUILD_DISTANCE or needs_rebuild:
		_rebuild_grass(player_pos)
		last_player_pos = player_pos
		needs_rebuild = false

func _rebuild_grass(center: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	# Deterministic seed based on rounded position so grass doesn't randomly shift
	var grid_x := int(center.x / REBUILD_DISTANCE) * int(REBUILD_DISTANCE)
	var grid_z := int(center.z / REBUILD_DISTANCE) * int(REBUILD_DISTANCE)
	rng.seed = world_seed + grid_x * 73856093 + grid_z * 19349663

	var placed := 0
	var attempts := 0
	var max_attempts := GRASS_COUNT * 3

	while placed < GRASS_COUNT and attempts < max_attempts:
		attempts += 1

		# Random position in circle around player
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * GRASS_RADIUS  # sqrt for uniform distribution
		var world_x := center.x + cos(angle) * dist
		var world_z := center.z + sin(angle) * dist

		# Get terrain height
		var height: float = terrain_world.get_terrain_height_at(Vector2(world_x, world_z))

		# Skip if underground or too high
		if height < -5.0 or height > 30.0:
			continue

		# Biome check
		var biome: String = terrain_world.get_biome_at(Vector2(world_x, world_z))
		if biome != "valley":
			continue

		# Place grass
		var pos := Vector3(world_x, height, world_z)
		var rot_y := rng.randf() * TAU
		var scale_f := rng.randf_range(0.7, 1.3)
		var basis := Basis.from_euler(Vector3(0, rot_y, 0)) * Basis.from_scale(Vector3(scale_f, scale_f, scale_f))
		grass_multimesh.set_instance_transform(placed, Transform3D(basis, pos))
		placed += 1

	# Hide any unused instances
	for i in range(placed, GRASS_COUNT):
		grass_multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

func _get_local_player() -> Node3D:
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p.has_method("is_local") and p.is_local():
			return p
		if "is_local_player" in p and p.is_local_player:
			return p
	# Fallback: find any player
	if players.size() > 0:
		return players[0]
	return null

func on_chunk_loaded(_chunk_pos: Vector2i) -> void:
	needs_rebuild = true

func on_chunk_unloaded(_chunk_pos: Vector2i) -> void:
	pass  # Grass auto-rebuilds around player anyway

func cleanup() -> void:
	if grass_mmi and is_instance_valid(grass_mmi):
		grass_mmi.queue_free()
	grass_mmi = null
	grass_multimesh = null
	is_initialized = false
