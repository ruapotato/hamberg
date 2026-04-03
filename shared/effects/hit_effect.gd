extends Node3D
class_name HitEffect

## HitEffect - Visual feedback when damage is dealt
## Spawns particles and a brief flash at hit location

@export var effect_color: Color = Color(1, 0.5, 0.2)
@export var is_critical: bool = false

var mesh: MeshInstance3D
var light: OmniLight3D
var particles: GPUParticles3D

# Manual animation state (no tweens/await)
var _anim_timer: float = 0.0
var _lifetime: float = 0.5
var _start_light_energy: float = 2.0


func _ready() -> void:
	_create_effect()
	_anim_timer = 0.0


func _process(delta: float) -> void:
	_anim_timer += delta

	# Animate manually (no tweens)
	var scale_up_end := 0.1
	var fade_end := 0.3

	if _anim_timer < scale_up_end:
		# Scale up mesh
		var progress := _anim_timer / scale_up_end
		if mesh:
			mesh.scale = Vector3.ONE * lerpf(1.0, 1.5, progress)
	elif _anim_timer < fade_end:
		# Fade light and scale down mesh
		var progress := (_anim_timer - scale_up_end) / (fade_end - scale_up_end)
		if light:
			light.light_energy = lerpf(_start_light_energy, 0.0, progress)
		if mesh:
			mesh.scale = Vector3.ONE * lerpf(1.5, 0.1, progress)

	# Destroy when done
	if _anim_timer >= _lifetime:
		queue_free()


func _create_effect() -> void:
	# Flash mesh
	mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.1 if not is_critical else 0.15
	sphere.height = 0.2 if not is_critical else 0.3
	mesh.mesh = sphere

	var material = StandardMaterial3D.new()
	material.albedo_color = effect_color
	material.emission_enabled = true
	material.emission = effect_color
	material.emission_energy_multiplier = 5.0 if is_critical else 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	add_child(mesh)

	# Light flash
	light = OmniLight3D.new()
	light.light_color = effect_color
	light.light_energy = 3.0 if is_critical else 2.0
	light.omni_range = 3.0 if is_critical else 2.0
	light.omni_attenuation = 2.0
	add_child(light)

	# Particles
	particles = GPUParticles3D.new()
	particles.amount = 20 if is_critical else 12
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true

	var particle_mat = ParticleProcessMaterial.new()
	particle_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_mat.emission_sphere_radius = 0.1
	particle_mat.direction = Vector3(0, 1, 0)
	particle_mat.spread = 180.0
	particle_mat.initial_velocity_min = 2.0
	particle_mat.initial_velocity_max = 5.0
	particle_mat.gravity = Vector3(0, -8, 0)
	particle_mat.scale_min = 0.03
	particle_mat.scale_max = 0.08
	particle_mat.color = effect_color

	var gradient = Gradient.new()
	gradient.colors = [effect_color, effect_color * 0.5, Color(0, 0, 0, 0)]
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	particle_mat.color_ramp = ramp

	particles.process_material = particle_mat

	var particle_mesh = SphereMesh.new()
	particle_mesh.radius = 0.03
	particle_mesh.height = 0.06
	particles.draw_pass_1 = particle_mesh
	add_child(particles)

	# Store light energy for animation (no tweens)
	_start_light_energy = light.light_energy


## Static helper to spawn a hit effect at a position
static func spawn_at(parent: Node, pos: Vector3, color: Color = Color(1, 0.5, 0.2), critical: bool = false) -> void:
	var effect = HitEffect.new()
	effect.effect_color = color
	effect.is_critical = critical
	parent.add_child(effect)
	effect.global_position = pos
