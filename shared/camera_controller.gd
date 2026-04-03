extends Node3D
class_name CameraController

## CameraController - First-person camera with optional third-person fallback
## Inspired by MvZ first-person controls, adapted for Hamberg's multiplayer

enum CameraMode { FIRST_PERSON, THIRD_PERSON }

@export var mouse_sensitivity: float = 0.002
@export var gamepad_sensitivity: float = 3.0
@export var min_zoom: float = 0.0
@export var max_zoom: float = 10.0
@export var zoom_speed: float = 0.5
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0
@export var first_person_eye_height: float = 1.6  # Eye height in first-person mode
@export var third_person_height_offset: float = 0.5

# Camera components
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

# Aim raycast for targeting (added dynamically)
var aim_raycast: RayCast3D = null
# Spell spawn point (Marker3D, 1 unit forward of camera)
var spell_spawn_point: Marker3D = null

# Camera state
var camera_mode: CameraMode = CameraMode.FIRST_PERSON
var camera_rotation: Vector2 = Vector2.ZERO  # x = yaw, y = pitch
var target_zoom: float = 3.0
var is_mouse_captured: bool = false
var is_first_person: bool = true
var lock_rotation: bool = false  # When true, ignores mouse input (for blocking)

# Screen shake for combat feedback
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_timer: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Start in first-person mode
	_apply_camera_mode()

	# Capture mouse by default when in game
	_capture_mouse()

	# Create AimRaycast on the camera
	aim_raycast = RayCast3D.new()
	aim_raycast.name = "AimRaycast"
	aim_raycast.target_position = Vector3(0, 0, -200)  # 200 units forward (camera looks along -Z)
	aim_raycast.collision_mask = 0xFFFFFFFF  # All layers
	aim_raycast.enabled = true
	camera.add_child(aim_raycast)

	# Create SpellSpawnPoint (Marker3D) 1 unit forward of camera
	spell_spawn_point = Marker3D.new()
	spell_spawn_point.name = "SpellSpawnPoint"
	spell_spawn_point.position = Vector3(0, 0, -1)  # 1 unit forward
	camera.add_child(spell_spawn_point)

func _input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if is_mouse_captured:
			_release_mouse()
		else:
			_capture_mouse()
		return

	# Toggle camera mode with V key
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		if camera_mode == CameraMode.FIRST_PERSON:
			camera_mode = CameraMode.THIRD_PERSON
		else:
			camera_mode = CameraMode.FIRST_PERSON
		_apply_camera_mode()
		return

	# Mouse look (only when captured and not locked)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not lock_rotation:
		_handle_mouse_look(event.relative)

	# Scroll wheel zoom (only in third-person)
	if event is InputEventMouseButton and camera_mode == CameraMode.THIRD_PERSON:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = max(min_zoom, target_zoom - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = min(max_zoom, target_zoom + zoom_speed)

func _process(delta: float) -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		_process_first_person(delta)
	else:
		_process_third_person(delta)

	# Handle gamepad camera look (right stick)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not lock_rotation:
		var look_x := Input.get_axis("look_left", "look_right")
		var look_y := Input.get_axis("look_up", "look_down")

		if abs(look_x) > 0.01 or abs(look_y) > 0.01:
			_handle_gamepad_look(Vector2(look_x, look_y), delta)

	# Process screen shake
	if shake_timer > 0:
		shake_timer -= delta
		var shake_progress = shake_timer / shake_duration if shake_duration > 0 else 0
		var current_intensity = shake_intensity * shake_progress
		shake_offset = Vector3(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity),
			0
		)
	else:
		shake_offset = Vector3.ZERO

func _process_first_person(delta: float) -> void:
	# In first-person, yaw rotates the player (this node's parent)
	# and pitch tilts the camera via the spring arm
	is_first_person = true
	spring_arm.spring_length = 0.0  # Camera right at the spring arm origin

	# Apply rotation: yaw on this node, pitch on spring arm
	rotation.y = camera_rotation.x
	spring_arm.rotation.x = camera_rotation.y + shake_offset.y * 0.02
	spring_arm.position = Vector3(shake_offset.x * 0.05, first_person_eye_height, 0)

func _process_third_person(delta: float) -> void:
	# Smooth zoom
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_zoom, 10.0 * delta)

	# Check if we're close enough to be effectively first-person
	is_first_person = spring_arm.spring_length < 0.5

	# Hide player mesh in first-person mode (from zoom)
	var player = get_parent()
	if player:
		var body = player.get_node_or_null("PlayerBody")
		if body:
			var sprite = body.get_node_or_null("BodySprite")
			if sprite:
				sprite.visible = not is_first_person

	# Apply camera rotation with shake
	rotation.y = camera_rotation.x
	spring_arm.rotation.x = camera_rotation.y + shake_offset.y * 0.02
	spring_arm.position = Vector3(shake_offset.x * 0.05, third_person_height_offset, 0)

func _apply_camera_mode() -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		spring_arm.spring_length = 0.0
		spring_arm.position = Vector3(0, first_person_eye_height, 0)
		is_first_person = true
		# Hide local player sprite in first-person
		_set_local_sprite_visible(false)
	else:
		spring_arm.spring_length = target_zoom
		spring_arm.position = Vector3(0, third_person_height_offset, 0)
		is_first_person = target_zoom < 0.5
		_set_local_sprite_visible(true)

func _set_local_sprite_visible(visible: bool) -> void:
	var player = get_parent()
	if player:
		var body = player.get_node_or_null("PlayerBody")
		if body:
			var sprite = body.get_node_or_null("BodySprite")
			if sprite:
				sprite.visible = visible

func _handle_mouse_look(mouse_delta: Vector2) -> void:
	# Yaw (left/right)
	camera_rotation.x -= mouse_delta.x * mouse_sensitivity

	# Pitch (up/down) with limits
	camera_rotation.y -= mouse_delta.y * mouse_sensitivity
	camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

func _handle_gamepad_look(stick_input: Vector2, delta: float) -> void:
	# Yaw (left/right)
	camera_rotation.x -= stick_input.x * gamepad_sensitivity * delta

	# Pitch (up/down) with limits
	camera_rotation.y += stick_input.y * gamepad_sensitivity * delta
	camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	is_mouse_captured = true

func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_mouse_captured = false

## Get the camera's forward direction (useful for movement)
func get_camera_forward() -> Vector3:
	return -camera.global_transform.basis.z

## Get the camera's right direction
func get_camera_right() -> Vector3:
	return camera.global_transform.basis.x

## Get camera for external access
func get_camera() -> Camera3D:
	return camera

## Get the point where the crosshair is aiming (for spell/combat targeting)
func get_aim_target() -> Dictionary:
	if aim_raycast and aim_raycast.is_colliding():
		return {
			"position": aim_raycast.get_collision_point(),
			"normal": aim_raycast.get_collision_normal(),
			"collider": aim_raycast.get_collider()
		}
	# No hit - return a point far in front of camera
	if camera:
		return {
			"position": camera.global_position - camera.global_transform.basis.z * 200.0,
			"normal": Vector3.UP,
			"collider": null
		}
	return {}

## Get the spell spawn point position
func get_spell_spawn_position() -> Vector3:
	if spell_spawn_point:
		return spell_spawn_point.global_position
	# Fallback: 1 unit in front of camera
	if camera:
		return camera.global_position - camera.global_transform.basis.z * 1.0
	return Vector3.ZERO

## Trigger screen shake for combat feedback
func shake(intensity: float = 1.0, duration: float = 0.15) -> void:
	shake_intensity = intensity
	shake_duration = duration
	shake_timer = duration
