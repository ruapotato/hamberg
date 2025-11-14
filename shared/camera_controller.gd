extends Node3D
class_name CameraController

## CameraController - Third-person camera with mouse look and zoom
## Attach this to the player and it will provide smooth camera controls

@export var mouse_sensitivity: float = 0.003
@export var min_zoom: float = 2.0
@export var max_zoom: float = 10.0
@export var zoom_speed: float = 0.5
@export var min_pitch: float = -80.0
@export var max_pitch: float = 80.0

# Camera components
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

# Camera state
var camera_rotation: Vector2 = Vector2.ZERO  # x = yaw, y = pitch
var target_zoom: float = 5.0
var is_mouse_captured: bool = false

func _ready() -> void:
	# Set initial zoom
	spring_arm.spring_length = target_zoom

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
