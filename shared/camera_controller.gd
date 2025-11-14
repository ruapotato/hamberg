extends Node3D
class_name CameraController

## CameraController - Third-person camera with mouse look and zoom
## Attach this to the player and it will provide smooth camera controls

@export var mouse_sensitivity: float = 0.003
@export var min_zoom: float = 0.0  # 0 = first-person
@export var max_zoom: float = 10.0
@export var zoom_speed: float = 0.5
@export var min_pitch: float = -80.0
@export var max_pitch: float = 80.0
@export var first_person_threshold: float = 0.5  # Distance at which to switch to first-person
@export var camera_height_offset: float = 0.5  # Camera positioned higher to show player lower on screen

# Camera components
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

# Camera state
var camera_rotation: Vector2 = Vector2.ZERO  # x = yaw, y = pitch
var target_zoom: float = 3.0  # Valheim-like default distance
var is_mouse_captured: bool = false
var is_first_person: bool = false

func _ready() -> void:
	# Set initial zoom
	spring_arm.spring_length = target_zoom

	# Adjust camera height for Valheim-like perspective
	spring_arm.position.y = camera_height_offset

	# Capture mouse by default when in game
	_capture_mouse()

func _input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if is_mouse_captured:
			_release_mouse()
		else:
			_capture_mouse()
		return

	# Mouse look (only when captured)
	if event is InputEventMouseMotion and is_mouse_captured:
		_handle_mouse_look(event.relative)

	# Scroll wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = max(min_zoom, target_zoom - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = min(max_zoom, target_zoom + zoom_speed)

func _process(delta: float) -> void:
	# Smooth zoom
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_zoom, 10.0 * delta)

	# Check if we're in first-person mode
	is_first_person = spring_arm.spring_length < first_person_threshold

	# Hide player mesh in first-person mode
	var player = get_parent()
	if player:
		var mesh = player.get_node_or_null("MeshInstance3D")
		if mesh:
			mesh.visible = not is_first_person

	# Apply camera rotation
	rotation.y = camera_rotation.x
	spring_arm.rotation.x = camera_rotation.y

func _handle_mouse_look(mouse_delta: Vector2) -> void:
	# Yaw (left/right)
	camera_rotation.x -= mouse_delta.x * mouse_sensitivity

	# Pitch (up/down) with limits
	camera_rotation.y -= mouse_delta.y * mouse_sensitivity
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
