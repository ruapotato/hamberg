extends RefCounted
class_name MultimeshMeshes

## Preloaded mesh and material resources for MultiMesh environmental objects
## Each object type defines its mesh components with local transforms

# Mesh definition: contains mesh, material, and local transform offset
class MeshDef:
	var mesh: Mesh
	var material: Material
	var local_transform: Transform3D

	func _init(m: Mesh, mat: Material, t: Transform3D = Transform3D.IDENTITY):
		mesh = m
		material = mat
		local_transform = t

# Object type definition: contains all meshes for one environmental object
class ObjectDef:
	var mesh_defs: Array[MeshDef] = []
	var collision_radius: float = 0.5
	var collision_height: float = 1.0
	var cull_distance: float = 50.0
	var max_health: float = 50.0
	var resource_drops: Dictionary = {}

static var _instance = null
var object_defs: Dictionary = {}  # object_type -> ObjectDef

static func get_instance():
	if _instance == null:
		_instance = new()
		_instance._setup_meshes()
	return _instance

func _setup_meshes() -> void:
	_setup_glowing_mushroom()
	_setup_spore_cluster()
	_setup_mushroom_tree()
	_setup_giant_mushroom()
	_setup_tree()
	_setup_rock()
	_setup_grass()

func _setup_glowing_mushroom() -> void:
	var obj_def := ObjectDef.new()

	# Stem mesh
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.06
	stem_mesh.bottom_radius = 0.08
	stem_mesh.height = 0.4
	stem_mesh.radial_segments = 5

	# Cap mesh
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.2
	cap_mesh.height = 0.15
	cap_mesh.radial_segments = 6
	cap_mesh.rings = 3

	# Materials
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.6, 0.55, 0.5, 1)

	var cap_mat_cyan := StandardMaterial3D.new()
	cap_mat_cyan.albedo_color = Color(0.1, 0.3, 0.35, 1)
	cap_mat_cyan.emission_enabled = true
	cap_mat_cyan.emission = Color(0.0, 0.8, 0.7, 1)
	cap_mat_cyan.emission_energy_multiplier = 1.5

	var cap_mat_purple := StandardMaterial3D.new()
	cap_mat_purple.albedo_color = Color(0.25, 0.1, 0.35, 1)
	cap_mat_purple.emission_enabled = true
	cap_mat_purple.emission = Color(0.5, 0.1, 0.8, 1)
	cap_mat_purple.emission_energy_multiplier = 1.2

	# 4 stems + 4 caps arranged in cluster
	obj_def.mesh_defs.append(MeshDef.new(stem_mesh, stem_mat, Transform3D(Basis(), Vector3(0, 0.2, 0))))
	obj_def.mesh_defs.append(MeshDef.new(cap_mesh, cap_mat_cyan, Transform3D(Basis.from_scale(Vector3(1.2, 1, 1.2)), Vector3(0, 0.45, 0))))

	obj_def.mesh_defs.append(MeshDef.new(stem_mesh, stem_mat, Transform3D(Basis.from_scale(Vector3(0.7, 0.8, 0.7)), Vector3(0.25, 0.16, 0.1))))
	obj_def.mesh_defs.append(MeshDef.new(cap_mesh, cap_mat_purple, Transform3D(Basis.from_scale(Vector3(0.8, 0.9, 0.8)), Vector3(0.25, 0.38, 0.1))))

	obj_def.mesh_defs.append(MeshDef.new(stem_mesh, stem_mat, Transform3D(Basis.from_scale(Vector3(0.5, 0.6, 0.5)), Vector3(-0.2, 0.12, -0.15))))
	obj_def.mesh_defs.append(MeshDef.new(cap_mesh, cap_mat_cyan, Transform3D(Basis.from_scale(Vector3(0.6, 0.7, 0.6)), Vector3(-0.2, 0.3, -0.15))))

	obj_def.mesh_defs.append(MeshDef.new(stem_mesh, stem_mat, Transform3D(Basis.from_scale(Vector3(0.4, 0.5, 0.4)), Vector3(0.1, 0.1, -0.25))))
	obj_def.mesh_defs.append(MeshDef.new(cap_mesh, cap_mat_purple, Transform3D(Basis.from_scale(Vector3(0.5, 0.5, 0.5)), Vector3(0.1, 0.25, -0.25))))

	obj_def.collision_radius = 0.4
	obj_def.collision_height = 0.5
	obj_def.cull_distance = 30.0
	obj_def.max_health = 30.0
	obj_def.resource_drops = {"glowing_spore": 2}

	object_defs["glowing_mushroom"] = obj_def

func _setup_spore_cluster() -> void:
	var obj_def := ObjectDef.new()

	# Spore meshes
	var spore_large := SphereMesh.new()
	spore_large.radius = 0.08
	spore_large.height = 0.16
	spore_large.radial_segments = 5
	spore_large.rings = 3

	var spore_small := SphereMesh.new()
	spore_small.radius = 0.04
	spore_small.height = 0.08
	spore_small.radial_segments = 4
	spore_small.rings = 2

	# Materials
	var spore_mat_green := StandardMaterial3D.new()
	spore_mat_green.albedo_color = Color(0.05, 0.15, 0.1, 1)
	spore_mat_green.emission_enabled = true
	spore_mat_green.emission = Color(0.0, 0.9, 0.4, 1)
	spore_mat_green.emission_energy_multiplier = 2.0

	var spore_mat_cyan := StandardMaterial3D.new()
	spore_mat_cyan.albedo_color = Color(0.05, 0.12, 0.15, 1)
	spore_mat_cyan.emission_enabled = true
	spore_mat_cyan.emission = Color(0.0, 0.7, 0.8, 1)
	spore_mat_cyan.emission_energy_multiplier = 1.8

	# 5 large + 5 small spores
	obj_def.mesh_defs.append(MeshDef.new(spore_large, spore_mat_green, Transform3D(Basis(), Vector3(0, 0.3, 0))))
	obj_def.mesh_defs.append(MeshDef.new(spore_large, spore_mat_cyan, Transform3D(Basis.from_scale(Vector3(0.8, 0.8, 0.8)), Vector3(0.15, 0.5, 0.1))))
	obj_def.mesh_defs.append(MeshDef.new(spore_large, spore_mat_green, Transform3D(Basis.from_scale(Vector3(0.7, 0.7, 0.7)), Vector3(-0.12, 0.65, -0.08))))
	obj_def.mesh_defs.append(MeshDef.new(spore_large, spore_mat_cyan, Transform3D(Basis.from_scale(Vector3(0.6, 0.6, 0.6)), Vector3(0.08, 0.85, 0.12))))
	obj_def.mesh_defs.append(MeshDef.new(spore_small, spore_mat_green, Transform3D(Basis.from_scale(Vector3(0.5, 0.5, 0.5)), Vector3(-0.1, 1.0, 0.05))))

	obj_def.mesh_defs.append(MeshDef.new(spore_small, spore_mat_green, Transform3D(Basis(), Vector3(0.2, 0.4, -0.05))))
	obj_def.mesh_defs.append(MeshDef.new(spore_small, spore_mat_cyan, Transform3D(Basis(), Vector3(-0.18, 0.45, 0.12))))
	obj_def.mesh_defs.append(MeshDef.new(spore_small, spore_mat_green, Transform3D(Basis(), Vector3(0.05, 0.75, -0.15))))
	obj_def.mesh_defs.append(MeshDef.new(spore_small, spore_mat_cyan, Transform3D(Basis(), Vector3(-0.08, 0.9, 0.18))))
	obj_def.mesh_defs.append(MeshDef.new(spore_small, spore_mat_green, Transform3D(Basis(), Vector3(0.12, 1.05, -0.06))))

	obj_def.collision_radius = 0.5
	obj_def.collision_height = 1.2
	obj_def.cull_distance = 28.0
	obj_def.max_health = 25.0
	obj_def.resource_drops = {"glowing_spore": 3}

	object_defs["spore_cluster"] = obj_def

func _setup_mushroom_tree() -> void:
	var obj_def := ObjectDef.new()

	# Stem mesh
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.4
	stem_mesh.bottom_radius = 0.6
	stem_mesh.height = 8.0
	stem_mesh.radial_segments = 6

	# Cap mesh
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.3
	cap_mesh.bottom_radius = 4.5
	cap_mesh.height = 1.8
	cap_mesh.radial_segments = 6

	# Cap top mesh
	var cap_top := SphereMesh.new()
	cap_top.radius = 1.2
	cap_top.height = 1.5
	cap_top.radial_segments = 6
	cap_top.rings = 3

	# Materials
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.15, 0.12, 0.18, 1)
	stem_mat.emission_enabled = true
	stem_mat.emission = Color(0.1, 0.05, 0.15, 1)
	stem_mat.emission_energy_multiplier = 0.3

	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.08, 0.15, 0.25, 1)
	cap_mat.emission_enabled = true
	cap_mat.emission = Color(0.0, 0.3, 0.5, 1)
	cap_mat.emission_energy_multiplier = 0.8

	obj_def.mesh_defs.append(MeshDef.new(stem_mesh, stem_mat, Transform3D(Basis(), Vector3(0, 4.0, 0))))
	obj_def.mesh_defs.append(MeshDef.new(cap_mesh, cap_mat, Transform3D(Basis(), Vector3(0, 8.5, 0))))
	obj_def.mesh_defs.append(MeshDef.new(cap_top, cap_mat, Transform3D(Basis(), Vector3(0, 9.8, 0))))

	obj_def.collision_radius = 0.6
	obj_def.collision_height = 8.0
	obj_def.cull_distance = 55.0
	obj_def.max_health = 100.0
	obj_def.resource_drops = {"fungal_wood": 4}

	object_defs["mushroom_tree"] = obj_def

func _setup_giant_mushroom() -> void:
	var obj_def := ObjectDef.new()

	# Stem mesh
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.8
	stem_mesh.bottom_radius = 1.2
	stem_mesh.height = 18.0
	stem_mesh.radial_segments = 6

	# Cap mesh
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.5
	cap_mesh.bottom_radius = 8.0
	cap_mesh.height = 3.0
	cap_mesh.radial_segments = 6

	# Cap dome
	var cap_dome := SphereMesh.new()
	cap_dome.radius = 2.5
	cap_dome.height = 3.0
	cap_dome.radial_segments = 6
	cap_dome.rings = 3

	# Cap ring
	var cap_ring := TorusMesh.new()
	cap_ring.inner_radius = 5.5
	cap_ring.outer_radius = 7.5
	cap_ring.rings = 6
	cap_ring.ring_segments = 8

	# Materials
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.12, 0.1, 0.16, 1)
	stem_mat.emission_enabled = true
	stem_mat.emission = Color(0.08, 0.04, 0.12, 1)
	stem_mat.emission_energy_multiplier = 0.2

	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.05, 0.12, 0.2, 1)
	cap_mat.emission_enabled = true
	cap_mat.emission = Color(0.0, 0.25, 0.45, 1)
	cap_mat.emission_energy_multiplier = 1.0

	obj_def.mesh_defs.append(MeshDef.new(stem_mesh, stem_mat, Transform3D(Basis(), Vector3(0, 9.0, 0))))
	obj_def.mesh_defs.append(MeshDef.new(cap_mesh, cap_mat, Transform3D(Basis(), Vector3(0, 18.5, 0))))
	obj_def.mesh_defs.append(MeshDef.new(cap_dome, cap_mat, Transform3D(Basis(), Vector3(0, 20.5, 0))))
	obj_def.mesh_defs.append(MeshDef.new(cap_ring, cap_mat, Transform3D(Basis(), Vector3(0, 18.0, 0))))

	obj_def.collision_radius = 1.2
	obj_def.collision_height = 18.0
	obj_def.cull_distance = 70.0
	obj_def.max_health = 180.0
	obj_def.resource_drops = {"fungal_wood": 8}

	object_defs["giant_mushroom"] = obj_def

func _setup_tree() -> void:
	var obj_def := ObjectDef.new()

	# Trunk mesh
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 3.0

	# Foliage mesh
	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 1.5
	foliage_mesh.height = 3.0

	# Materials
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.15, 1)

	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.2, 0.5, 0.2, 1)

	obj_def.mesh_defs.append(MeshDef.new(trunk_mesh, trunk_mat, Transform3D(Basis(), Vector3(0, 1.5, 0))))
	obj_def.mesh_defs.append(MeshDef.new(foliage_mesh, foliage_mat, Transform3D(Basis(), Vector3(0, 3.5, 0))))

	obj_def.collision_radius = 0.25
	obj_def.collision_height = 3.0
	obj_def.cull_distance = 100.0
	obj_def.max_health = 100.0
	obj_def.resource_drops = {"wood": 3}

	object_defs["tree"] = obj_def

func _setup_rock() -> void:
	var obj_def := ObjectDef.new()

	# Rock mesh
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8
	rock_mesh.height = 1.2
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 6

	# Material
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.5, 0.5, 0.55, 1)

	obj_def.mesh_defs.append(MeshDef.new(rock_mesh, rock_mat, Transform3D(Basis.from_scale(Vector3(1, 0.7, 1.2)), Vector3(0, 0.5, 0))))

	obj_def.collision_radius = 0.8
	obj_def.collision_height = 1.0
	obj_def.cull_distance = 80.0
	obj_def.max_health = 150.0
	obj_def.resource_drops = {"stone": 5}

	object_defs["rock"] = obj_def

func _setup_grass() -> void:
	var obj_def := ObjectDef.new()

	# Grass blade mesh - thin and delicate
	var grass_blade := QuadMesh.new()
	grass_blade.size = Vector2(0.08, 0.35)

	# Material - slightly deeper green
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.25, 0.55, 0.2, 1)
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	# 5 thin blades per clump
	obj_def.mesh_defs.append(MeshDef.new(grass_blade, grass_mat, Transform3D(Basis(), Vector3(0, 0.18, 0))))
	obj_def.mesh_defs.append(MeshDef.new(grass_blade, grass_mat, Transform3D(Basis.from_euler(Vector3(0, PI/6, 0)), Vector3(0.06, 0.16, 0.03))))
	obj_def.mesh_defs.append(MeshDef.new(grass_blade, grass_mat, Transform3D(Basis.from_euler(Vector3(0, -PI/3, 0)), Vector3(-0.05, 0.17, -0.04))))
	obj_def.mesh_defs.append(MeshDef.new(grass_blade, grass_mat, Transform3D(Basis.from_euler(Vector3(0, PI/4, 0)), Vector3(0.04, 0.15, -0.05))))
	obj_def.mesh_defs.append(MeshDef.new(grass_blade, grass_mat, Transform3D(Basis.from_euler(Vector3(0, -PI/12, 0)), Vector3(-0.03, 0.19, 0.05))))

	obj_def.collision_radius = 0.0  # No collision for grass
	obj_def.collision_height = 0.0
	obj_def.cull_distance = 25.0
	obj_def.max_health = 10.0
	obj_def.resource_drops = {}

	object_defs["grass"] = obj_def

func get_object_def(object_type: String) -> ObjectDef:
	return object_defs.get(object_type)

func get_supported_types() -> Array:
	return object_defs.keys()
