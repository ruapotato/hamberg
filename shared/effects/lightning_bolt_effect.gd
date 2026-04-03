extends Node3D
class_name LightningBoltEffect

## Simple lightning bolt visual - just cylinders with glow

@export var bolt_height: float = 25.0
@export var lifetime: float = 0.12

var _time_left: float = 0.0

func _ready() -> void:
	_time_left = lifetime
	_create_simple_bolt()

func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0:
		queue_free()

func _create_simple_bolt() -> void:
	# Main bolt - simple cylinder
	var main_bolt := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.2
	cyl.height = bolt_height
	main_bolt.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.8, 1.0)
	mat.emission_energy_multiplier = 5.0
	main_bolt.material_override = mat

	add_child(main_bolt)
	main_bolt.position = Vector3(0, bolt_height / 2.0, 0)

	# Core glow - thinner bright center
	var core := MeshInstance3D.new()
	var core_cyl := CylinderMesh.new()
	core_cyl.top_radius = 0.05
	core_cyl.bottom_radius = 0.08
	core_cyl.height = bolt_height
	core.mesh = core_cyl

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 1.0, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 1.0, 1.0)
	core_mat.emission_energy_multiplier = 10.0
	core.material_override = core_mat

	add_child(core)
	core.position = Vector3(0, bolt_height / 2.0, 0)

	# Flash light at ground
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.7, 0.85, 1.0)
	flash.light_energy = 10.0
	flash.omni_range = 15.0
	add_child(flash)
