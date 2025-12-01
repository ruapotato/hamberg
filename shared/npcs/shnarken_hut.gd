extends Node3D
class_name ShnarkenHut

## ShnarkenHut - Giant boot/shoe building that houses a Shnarken shopkeeper
## Complete with windows, door, chimney smoke, and decorations

const ShnarkenScene = preload("res://shared/npcs/shnarken.tscn")

@export var biome_id: int = 1
@export var hut_name: String = "Shnarken's Boot"

var shnarken: Node3D  # Shnarken NPC instance
var door_node: Node3D
var is_door_open: bool = false
var smoke_particles: GPUParticles3D

# Light from windows
var window_lights: Array[OmniLight3D] = []

func _ready() -> void:
	_setup_boot()
	_setup_decorations()
	_setup_lighting()
	_spawn_shnarken()

# =============================================================================
# BOOT STRUCTURE
# =============================================================================

func _setup_boot() -> void:
	# Check if boot structure already exists from .tscn scene
	var boot_structure = get_node_or_null("BootStructure")
	if boot_structure:
		door_node = boot_structure.get_node_or_null("Door")
		smoke_particles = get_node_or_null("ChimneySmoke")
		print("[ShnarkenHut] Using scene-based mesh (editable in Godot)")
		return

	# Fallback: Procedural generation
	print("[ShnarkenHut] Generating procedural mesh")
	var scale_factor: float = 1.0

	# === MATERIALS ===

	# Worn leather - brown with weathering
	var leather_mat = StandardMaterial3D.new()
	leather_mat.albedo_color = Color(0.4, 0.28, 0.18, 1)  # Brown leather
	leather_mat.roughness = 0.85

	# Darker leather (worn areas)
	var dark_leather_mat = StandardMaterial3D.new()
	dark_leather_mat.albedo_color = Color(0.3, 0.2, 0.12, 1)
	dark_leather_mat.roughness = 0.9

	# Sole material (rubber/darker)
	var sole_mat = StandardMaterial3D.new()
	sole_mat.albedo_color = Color(0.15, 0.12, 0.1, 1)
	sole_mat.roughness = 0.95

	# Lace material (tan cord)
	var lace_mat = StandardMaterial3D.new()
	lace_mat.albedo_color = Color(0.6, 0.5, 0.35, 1)
	lace_mat.roughness = 0.8

	# Window frame (wood)
	var wood_mat = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.32, 0.2, 1)
	wood_mat.roughness = 0.75

	# Window glass (warm glow)
	var glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(1.0, 0.9, 0.6, 0.4)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(1.0, 0.85, 0.5, 1)
	glass_mat.emission_energy_multiplier = 0.8

	# Metal (buckles, etc)
	var metal_mat = StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.5, 0.45, 0.4, 1)
	metal_mat.metallic = 0.7
	metal_mat.roughness = 0.5

	# === BOOT TOE (main building area) ===
	var toe = MeshInstance3D.new()
	var toe_mesh = SphereMesh.new()
	toe_mesh.radius = 2.5 * scale_factor
	toe_mesh.height = 3.5 * scale_factor
	toe.mesh = toe_mesh
	toe.material_override = leather_mat
	toe.position = Vector3(0, 1.8 * scale_factor, 2.0 * scale_factor)
	toe.scale = Vector3(1.2, 0.8, 1.5)  # Stretched for boot toe shape
	add_child(toe)

	# === BOOT SHAFT (ankle/leg area - chimney) ===
	var shaft = MeshInstance3D.new()
	var shaft_mesh = CylinderMesh.new()
	shaft_mesh.top_radius = 1.8 * scale_factor
	shaft_mesh.bottom_radius = 2.2 * scale_factor
	shaft_mesh.height = 4.0 * scale_factor
	shaft.mesh = shaft_mesh
	shaft.material_override = leather_mat
	shaft.position = Vector3(0, 3.5 * scale_factor, -1.5 * scale_factor)
	shaft.rotation.x = 0.15  # Slight lean back
	add_child(shaft)

	# Shaft opening (top - chimney hole)
	var shaft_rim = MeshInstance3D.new()
	var rim_mesh = TorusMesh.new()
	rim_mesh.inner_radius = 1.5 * scale_factor
	rim_mesh.outer_radius = 1.9 * scale_factor
	shaft_rim.mesh = rim_mesh
	shaft_rim.material_override = dark_leather_mat
	shaft_rim.position = Vector3(0, 5.5 * scale_factor, -1.8 * scale_factor)
	shaft_rim.rotation.x = PI / 2 + 0.15
	add_child(shaft_rim)

	# === SOLE (thick bottom) ===
	var sole = MeshInstance3D.new()
	var sole_mesh = BoxMesh.new()
	sole_mesh.size = Vector3(3.5, 0.5, 6.0) * scale_factor
	sole.mesh = sole_mesh
	sole.material_override = sole_mat
	sole.position = Vector3(0, 0.25 * scale_factor, 0.5 * scale_factor)
	add_child(sole)

	# Sole front curve
	var sole_front = MeshInstance3D.new()
	var sole_front_mesh = CylinderMesh.new()
	sole_front_mesh.top_radius = 1.7 * scale_factor
	sole_front_mesh.bottom_radius = 1.7 * scale_factor
	sole_front_mesh.height = 0.5 * scale_factor
	sole_front.mesh = sole_front_mesh
	sole_front.material_override = sole_mat
	sole_front.position = Vector3(0, 0.25 * scale_factor, 3.2 * scale_factor)
	sole_front.rotation.x = PI / 2
	add_child(sole_front)

	# === HEEL ===
	var heel = MeshInstance3D.new()
	var heel_mesh = BoxMesh.new()
	heel_mesh.size = Vector3(2.8, 1.0, 1.5) * scale_factor
	heel.mesh = heel_mesh
	heel.material_override = sole_mat
	heel.position = Vector3(0, 0.5 * scale_factor, -2.8 * scale_factor)
	add_child(heel)

	# === DOOR (where foot goes in) ===
	door_node = Node3D.new()
	door_node.name = "Door"
	door_node.position = Vector3(0, 0.8 * scale_factor, 4.2 * scale_factor)
	add_child(door_node)

	# Door frame
	var door_frame = MeshInstance3D.new()
	var frame_mesh = BoxMesh.new()
	frame_mesh.size = Vector3(1.4, 2.2, 0.15) * scale_factor
	door_frame.mesh = frame_mesh
	door_frame.material_override = wood_mat
	door_frame.position = Vector3(0, 1.0 * scale_factor, 0)
	door_node.add_child(door_frame)

	# Door (darker wood)
	var door = MeshInstance3D.new()
	var door_mesh = BoxMesh.new()
	door_mesh.size = Vector3(1.2, 2.0, 0.1) * scale_factor
	door.mesh = door_mesh
	door.material_override = dark_leather_mat
	door.position = Vector3(0, 1.0 * scale_factor, 0.08 * scale_factor)
	door_node.add_child(door)

	# Door handle
	var handle = MeshInstance3D.new()
	var handle_mesh = SphereMesh.new()
	handle_mesh.radius = 0.08 * scale_factor
	handle.mesh = handle_mesh
	handle.material_override = metal_mat
	handle.position = Vector3(0.4 * scale_factor, 1.0 * scale_factor, 0.15 * scale_factor)
	door_node.add_child(handle)

	# === WINDOWS (cut into sides) ===
	_create_window(Vector3(2.2 * scale_factor, 2.0 * scale_factor, 1.0 * scale_factor), 0.3, wood_mat, glass_mat)
	_create_window(Vector3(-2.2 * scale_factor, 2.0 * scale_factor, 1.0 * scale_factor), -0.3, wood_mat, glass_mat)
	_create_window(Vector3(1.8 * scale_factor, 2.5 * scale_factor, -0.5 * scale_factor), 0.5, wood_mat, glass_mat)
	_create_window(Vector3(-1.8 * scale_factor, 2.5 * scale_factor, -0.5 * scale_factor), -0.5, wood_mat, glass_mat)

	# === LACES (decorative, hanging loose) ===
	_create_laces(lace_mat, scale_factor)

	# === PATCHES (worn repairs) ===
	_create_patches(dark_leather_mat, scale_factor)

	# === SIGN ===
	_create_sign(wood_mat, scale_factor)

	# === COLLISION ===
	_setup_collision()

func _create_window(pos: Vector3, rot_y: float, wood_mat: Material, glass_mat: Material) -> void:
	var window = Node3D.new()
	window.position = pos
	window.rotation.y = rot_y
	add_child(window)

	# Frame
	var frame = MeshInstance3D.new()
	var frame_mesh = BoxMesh.new()
	frame_mesh.size = Vector3(0.8, 0.8, 0.1)
	frame.mesh = frame_mesh
	frame.material_override = wood_mat
	window.add_child(frame)

	# Glass (glowing)
	var glass = MeshInstance3D.new()
	var glass_mesh = BoxMesh.new()
	glass_mesh.size = Vector3(0.6, 0.6, 0.05)
	glass.mesh = glass_mesh
	glass.material_override = glass_mat
	glass.position.z = 0.03
	window.add_child(glass)

	# Cross frame
	var h_bar = MeshInstance3D.new()
	var bar_mesh = BoxMesh.new()
	bar_mesh.size = Vector3(0.6, 0.05, 0.08)
	h_bar.mesh = bar_mesh
	h_bar.material_override = wood_mat
	h_bar.position.z = 0.05
	window.add_child(h_bar)

	var v_bar = MeshInstance3D.new()
	v_bar.mesh = bar_mesh
	v_bar.material_override = wood_mat
	v_bar.rotation.z = PI / 2
	v_bar.position.z = 0.05
	window.add_child(v_bar)

	# Add light
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 0.5
	light.omni_range = 3.0
	light.position = pos - Vector3(0, 0, 0.5).rotated(Vector3.UP, rot_y)
	add_child(light)
	window_lights.append(light)

func _create_laces(lace_mat: Material, scale_factor: float) -> void:
	# Lace holes (eyelets) on shaft
	var metal_mat = StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.5, 0.45, 0.4, 1)
	metal_mat.metallic = 0.7

	for i in range(4):
		for side in [-1, 1]:
			# Eyelet
			var eyelet = MeshInstance3D.new()
			var eyelet_mesh = TorusMesh.new()
			eyelet_mesh.inner_radius = 0.06 * scale_factor
			eyelet_mesh.outer_radius = 0.1 * scale_factor
			eyelet.mesh = eyelet_mesh
			eyelet.material_override = metal_mat
			eyelet.position = Vector3(0.8 * side * scale_factor, 2.5 * scale_factor + i * 0.6 * scale_factor, 0.3 * scale_factor)
			eyelet.rotation.y = 0.3 * side
			add_child(eyelet)

	# Hanging laces (loose, broken)
	for side in [-1, 1]:
		var lace = MeshInstance3D.new()
		var lace_mesh = CylinderMesh.new()
		lace_mesh.top_radius = 0.03 * scale_factor
		lace_mesh.bottom_radius = 0.025 * scale_factor
		lace_mesh.height = 1.5 * scale_factor
		lace.mesh = lace_mesh
		lace.material_override = lace_mat
		lace.position = Vector3(0.8 * side * scale_factor, 4.0 * scale_factor, 0.4 * scale_factor)
		lace.rotation.x = 0.4
		lace.rotation.z = 0.6 * side
		add_child(lace)

func _create_patches(patch_mat: Material, scale_factor: float) -> void:
	# Worn patches on the boot
	var patch_positions = [
		Vector3(1.5, 1.5, 2.5),
		Vector3(-1.8, 2.2, 1.0),
		Vector3(0.5, 3.0, -1.0),
	]

	for pos in patch_positions:
		var patch = MeshInstance3D.new()
		var patch_mesh = BoxMesh.new()
		patch_mesh.size = Vector3(
			randf_range(0.4, 0.8),
			randf_range(0.3, 0.6),
			0.05
		) * scale_factor
		patch.mesh = patch_mesh
		patch.material_override = patch_mat
		patch.position = pos * scale_factor
		patch.rotation = Vector3(randf_range(-0.2, 0.2), randf_range(-0.3, 0.3), randf_range(-0.1, 0.1))
		add_child(patch)

		# Stitch marks around patch
		for j in range(4):
			var stitch = MeshInstance3D.new()
			var stitch_mesh = CylinderMesh.new()
			stitch_mesh.top_radius = 0.01 * scale_factor
			stitch_mesh.bottom_radius = 0.01 * scale_factor
			stitch_mesh.height = 0.08 * scale_factor
			stitch.mesh = stitch_mesh
			stitch.material_override = patch_mat
			var angle = j * PI / 2
			stitch.position = pos * scale_factor + Vector3(cos(angle) * 0.35, sin(angle) * 0.25, 0.06) * scale_factor
			stitch.rotation.x = PI / 2
			add_child(stitch)

func _create_sign(wood_mat: Material, scale_factor: float) -> void:
	# Hanging sign
	var sign_post = MeshInstance3D.new()
	var post_mesh = CylinderMesh.new()
	post_mesh.top_radius = 0.05 * scale_factor
	post_mesh.bottom_radius = 0.05 * scale_factor
	post_mesh.height = 1.0 * scale_factor
	sign_post.mesh = post_mesh
	sign_post.material_override = wood_mat
	sign_post.position = Vector3(2.0 * scale_factor, 2.5 * scale_factor, 4.0 * scale_factor)
	sign_post.rotation.z = -0.3
	add_child(sign_post)

	# Sign board
	var sign_board = MeshInstance3D.new()
	var board_mesh = BoxMesh.new()
	board_mesh.size = Vector3(1.2, 0.6, 0.08) * scale_factor
	sign_board.mesh = board_mesh
	sign_board.material_override = wood_mat
	sign_board.position = Vector3(2.3 * scale_factor, 2.0 * scale_factor, 4.0 * scale_factor)
	sign_board.rotation.z = 0.1  # Crooked
	add_child(sign_board)

	# TODO: Add text "SHNARKEN'S" via Label3D or texture

func _setup_collision() -> void:
	# Main collision for the boot (simplified)
	var static_body = StaticBody3D.new()
	static_body.collision_layer = 1  # World layer
	static_body.collision_mask = 0
	add_child(static_body)

	# Toe area collision
	var toe_col = CollisionShape3D.new()
	var toe_shape = BoxShape3D.new()
	toe_shape.size = Vector3(5.0, 3.5, 5.0)
	toe_col.shape = toe_shape
	toe_col.position = Vector3(0, 2.0, 1.5)
	static_body.add_child(toe_col)

	# Shaft collision
	var shaft_col = CollisionShape3D.new()
	var shaft_shape = CylinderShape3D.new()
	shaft_shape.radius = 2.0
	shaft_shape.height = 4.0
	shaft_col.shape = shaft_shape
	shaft_col.position = Vector3(0, 3.5, -1.5)
	static_body.add_child(shaft_col)

# =============================================================================
# DECORATIONS
# =============================================================================

func _setup_decorations() -> void:
	# Skip if using scene-based mesh
	if get_node_or_null("BootStructure"):
		return

	var wood_mat = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.32, 0.2, 1)
	wood_mat.roughness = 0.75

	# Wooden crates
	for i in range(2):
		var crate = MeshInstance3D.new()
		var crate_mesh = BoxMesh.new()
		crate_mesh.size = Vector3(0.6, 0.5, 0.6)
		crate.mesh = crate_mesh
		crate.material_override = wood_mat
		crate.position = Vector3(3.0 + i * 0.7, 0.25, 2.5 - i * 0.5)
		crate.rotation.y = randf_range(-0.3, 0.3)
		add_child(crate)

	# Barrel
	var barrel_mat = StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.5, 0.35, 0.2, 1)

	var barrel = MeshInstance3D.new()
	var barrel_mesh = CylinderMesh.new()
	barrel_mesh.top_radius = 0.35
	barrel_mesh.bottom_radius = 0.4
	barrel_mesh.height = 0.9
	barrel.mesh = barrel_mesh
	barrel.material_override = barrel_mat
	barrel.position = Vector3(-3.2, 0.45, 2.0)
	add_child(barrel)

	# Lantern post
	var post = MeshInstance3D.new()
	var post_mesh = CylinderMesh.new()
	post_mesh.top_radius = 0.05
	post_mesh.bottom_radius = 0.06
	post_mesh.height = 2.5
	post.mesh = post_mesh
	post.material_override = wood_mat
	post.position = Vector3(3.5, 1.25, 4.5)
	add_child(post)

	# Lantern
	var lantern_mat = StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(1.0, 0.8, 0.4, 1)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = Color(1.0, 0.7, 0.3, 1)
	lantern_mat.emission_energy_multiplier = 1.5

	var lantern = MeshInstance3D.new()
	var lantern_mesh = BoxMesh.new()
	lantern_mesh.size = Vector3(0.25, 0.35, 0.25)
	lantern.mesh = lantern_mesh
	lantern.material_override = lantern_mat
	lantern.position = Vector3(3.5, 2.7, 4.5)
	add_child(lantern)

	# Lantern light
	var lantern_light = OmniLight3D.new()
	lantern_light.light_color = Color(1.0, 0.8, 0.5)
	lantern_light.light_energy = 1.0
	lantern_light.omni_range = 6.0
	lantern_light.position = Vector3(3.5, 2.7, 4.5)
	add_child(lantern_light)

	# Mushrooms around base
	_add_mushrooms()

func _add_mushrooms() -> void:
	var mushroom_mat = StandardMaterial3D.new()
	mushroom_mat.albedo_color = Color(0.7, 0.5, 0.35, 1)

	var cap_mat = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.6, 0.2, 0.15, 1)

	var positions = [
		Vector3(-2.5, 0, 3.5),
		Vector3(-3.0, 0, 2.0),
		Vector3(2.8, 0, 3.0),
		Vector3(-2.0, 0, -2.0),
		Vector3(2.5, 0, -1.5),
	]

	for pos in positions:
		var mushroom = Node3D.new()
		mushroom.position = pos

		# Stem
		var stem = MeshInstance3D.new()
		var stem_mesh = CylinderMesh.new()
		var height = randf_range(0.15, 0.35)
		stem_mesh.top_radius = 0.04
		stem_mesh.bottom_radius = 0.05
		stem_mesh.height = height
		stem.mesh = stem_mesh
		stem.material_override = mushroom_mat
		stem.position.y = height / 2
		mushroom.add_child(stem)

		# Cap
		var cap = MeshInstance3D.new()
		var cap_mesh = SphereMesh.new()
		cap_mesh.radius = randf_range(0.08, 0.15)
		cap_mesh.height = cap_mesh.radius
		cap.mesh = cap_mesh
		cap.material_override = cap_mat
		cap.position.y = height + 0.02
		mushroom.add_child(cap)

		add_child(mushroom)

# =============================================================================
# LIGHTING & SMOKE
# =============================================================================

func _setup_lighting() -> void:
	# Check if using scene-based smoke
	smoke_particles = get_node_or_null("ChimneySmoke")
	if smoke_particles:
		# Just need to set up the particle material if not already set
		if not smoke_particles.process_material:
			_setup_smoke_material()
		return

	# Fallback: Procedural chimney smoke particles
	smoke_particles = GPUParticles3D.new()
	smoke_particles.name = "ChimneySmoke"
	smoke_particles.position = Vector3(0, 5.8, -1.8)
	smoke_particles.amount = 20
	smoke_particles.lifetime = 4.0
	smoke_particles.explosiveness = 0.0
	smoke_particles.randomness = 0.5

	_setup_smoke_material()

	add_child(smoke_particles)

func _setup_smoke_material() -> void:
	var smoke_mat = ParticleProcessMaterial.new()
	smoke_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_mat.emission_sphere_radius = 0.5
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 15.0
	smoke_mat.initial_velocity_min = 0.5
	smoke_mat.initial_velocity_max = 1.0
	smoke_mat.gravity = Vector3(0, 0.2, 0)
	smoke_mat.scale_min = 0.3
	smoke_mat.scale_max = 0.8
	smoke_mat.color = Color(0.4, 0.4, 0.4, 0.4)

	smoke_particles.process_material = smoke_mat

	# Smoke mesh (simple quad)
	var smoke_mesh = QuadMesh.new()
	smoke_mesh.size = Vector2(0.5, 0.5)
	smoke_particles.draw_pass_1 = smoke_mesh

# =============================================================================
# SHNARKEN SPAWN
# =============================================================================

func _spawn_shnarken() -> void:
	# Check if Shnarken already exists from .tscn scene
	shnarken = get_node_or_null("Shnarken")
	if shnarken:
		shnarken.biome_id = biome_id
		print("[ShnarkenHut] Using scene-based Shnarken")
		return

	# Fallback: Spawn the Shnarken NPC outside the hut
	if ShnarkenScene:
		shnarken = ShnarkenScene.instantiate()
		shnarken.biome_id = biome_id
		shnarken.position = Vector3(0, 0.1, 7.0)  # Outside, in front of boot
		add_child(shnarken)
		print("[ShnarkenHut] Spawned Shnarken NPC (hopping outside)")
