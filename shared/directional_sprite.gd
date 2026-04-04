extends Sprite3D

## DirectionalSprite - Multi-angle 2D billboard sprite for 3D worlds
##
## Supports two modes:
## 1. 36-angle mode: Uses set_character() to load 36 pre-rendered angle PNGs
##    for smooth 360-degree rotation (10 degrees per frame).
## 2. Legacy 4/8-direction mode: Uses set_textures_4dir/8dir for sector-based
##    texture selection.
##
## The sprite manually rotates on the Y axis to face the camera (like
## BILLBOARD_FIXED_Y) but does NOT use Godot's built-in billboard mode,
## since we need to control which texture is shown per angle sector.

# ============================================================================
# 36-ANGLE MODE
# ============================================================================

## Character name for 36-angle sprite loading
var _character_name: String = ""

## Array of 36 Texture2D (index 0 = 0 degrees, index 1 = 10 degrees, etc.)
var _angle_textures: Array = []

## Whether we are using the 36-angle system (vs legacy 4/8 dir)
var _use_36_angles: bool = false

# ============================================================================
# LEGACY TEXTURES (4/8-direction mode)
# ============================================================================

## Textures for each direction. Assign via set_textures_4dir/8dir or the dict method.
var texture_front: Texture2D = null
var texture_back: Texture2D = null
var texture_left: Texture2D = null
var texture_right: Texture2D = null
var texture_front_left: Texture2D = null
var texture_front_right: Texture2D = null
var texture_back_left: Texture2D = null
var texture_back_right: Texture2D = null

# ============================================================================
# CONFIGURATION
# ============================================================================

## The direction the entity faces in world space (radians, 0 = forward along -Z).
## Set this from the owning entity's movement/AI code.
var facing_angle: float = 0.0

## Number of directional texture variants: 4 or 8 (legacy mode only).
var num_angles: int = 4

# ============================================================================
# INTERNAL STATE
# ============================================================================

# Current angle sector index. -1 = uninitialised.
var _current_sector: int = -1

# Cached previous values for change detection
var _prev_camera_pos: Vector3 = Vector3.INF
var _prev_facing_angle: float = INF

# Minimum angular change (radians) before re-evaluating the sector (~5 degrees)
const ANGLE_CHANGE_THRESHOLD: float = 0.087

# ============================================================================
# PUBLIC API - 36-ANGLE MODE
# ============================================================================

## Load 36-angle sprites for a character via SpriteLoader.
## This is the preferred method for characters with full angle coverage.
func set_character(character_name: String) -> void:
	_character_name = character_name
	_angle_textures = SpriteLoader.load_character_angles(character_name)
	_use_36_angles = _angle_textures.size() == 36 and _angle_textures[0] != null
	if _use_36_angles:
		# Set initial texture to angle 0 (front)
		texture = _angle_textures[0]
	_current_sector = -1  # Force refresh

# ============================================================================
# PUBLIC API - LEGACY MODE
# ============================================================================

## Set textures for 4-direction mode (front, back, left, right).
func set_textures_4dir(front: Texture2D, back: Texture2D, left: Texture2D, right: Texture2D) -> void:
	_use_36_angles = false
	texture_front = front
	texture_back = back
	texture_left = left
	texture_right = right
	num_angles = 4
	_current_sector = -1  # Force refresh

## Set textures for 8-direction mode.
func set_textures_8dir(
	front: Texture2D, back: Texture2D, left: Texture2D, right: Texture2D,
	front_left: Texture2D, front_right: Texture2D,
	back_left: Texture2D, back_right: Texture2D
) -> void:
	_use_36_angles = false
	texture_front = front
	texture_back = back
	texture_left = left
	texture_right = right
	texture_front_left = front_left
	texture_front_right = front_right
	texture_back_left = back_left
	texture_back_right = back_right
	num_angles = 8
	_current_sector = -1

## Set textures from a Dictionary.
## Valid keys: "front", "back", "left", "right",
##             "front_left", "front_right", "back_left", "back_right"
func set_all_textures_from_dict(textures: Dictionary) -> void:
	_use_36_angles = false
	texture_front = textures.get("front")
	texture_back = textures.get("back")
	texture_left = textures.get("left")
	texture_right = textures.get("right")
	texture_front_left = textures.get("front_left")
	texture_front_right = textures.get("front_right")
	texture_back_left = textures.get("back_left")
	texture_back_right = textures.get("back_right")
	# Auto-detect num_angles
	if texture_front_left or texture_front_right or texture_back_left or texture_back_right:
		num_angles = 8
	else:
		num_angles = 4
	_current_sector = -1

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Disable Godot's built-in billboard -- we handle orientation manually.
	billboard = BaseMaterial3D.BILLBOARD_DISABLED

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var camera_pos := camera.global_position
	var sprite_world_pos := global_position

	# --- Y-axis billboard: rotate sprite to face camera on Y only ---
	var dir_to_camera := camera_pos - sprite_world_pos
	dir_to_camera.y = 0.0
	if dir_to_camera.length_squared() > 0.001:
		var desired_y := atan2(dir_to_camera.x, dir_to_camera.z)
		global_rotation.y = desired_y

	# --- Texture selection ---
	if _use_36_angles:
		_update_36_angle_texture(camera_pos, sprite_world_pos)
	else:
		_update_legacy_sector_texture(camera_pos, sprite_world_pos)

# ============================================================================
# 36-ANGLE TEXTURE SELECTION
# ============================================================================

func _update_36_angle_texture(camera_pos: Vector3, sprite_world_pos: Vector3) -> void:
	if _angle_textures.is_empty():
		return

	# Skip expensive recalc if nothing changed enough
	var cam_moved := (_prev_camera_pos - camera_pos).length_squared() > 0.01
	var facing_changed := absf(_prev_facing_angle - facing_angle) > ANGLE_CHANGE_THRESHOLD
	if not cam_moved and not facing_changed and _current_sector != -1:
		return

	_prev_camera_pos = camera_pos
	_prev_facing_angle = facing_angle

	var to_camera := camera_pos - sprite_world_pos
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.001:
		return

	var cam_angle := atan2(to_camera.x, to_camera.z)
	# relative: 0 = seeing front of entity, PI = seeing back
	# Adding PI flips so that when camera is opposite to facing, we see front
	var relative := rad_to_deg(cam_angle - facing_angle + PI)
	# Normalize to 0-360
	relative = fmod(relative, 360.0)
	if relative < 0:
		relative += 360.0
	var index := int(round(relative / 10.0)) % 36
	if index == _current_sector:
		return
	_current_sector = index
	var new_tex = _angle_textures[index]
	if new_tex and new_tex != texture:
		texture = new_tex
		flip_h = false

# ============================================================================
# LEGACY SECTOR-BASED TEXTURE SELECTION
# ============================================================================

func _update_legacy_sector_texture(camera_pos: Vector3, sprite_world_pos: Vector3) -> void:
	# Skip expensive recalc if nothing changed enough
	var cam_moved := (_prev_camera_pos - camera_pos).length_squared() > 0.01
	var facing_changed := absf(_prev_facing_angle - facing_angle) > ANGLE_CHANGE_THRESHOLD
	if not cam_moved and not facing_changed and _current_sector != -1:
		return

	_prev_camera_pos = camera_pos
	_prev_facing_angle = facing_angle

	# Compute relative angle: camera direction relative to entity facing.
	var to_camera := camera_pos - sprite_world_pos
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.001:
		return

	var angle_to_camera := atan2(to_camera.x, to_camera.z)
	var relative_angle := _wrap_angle(angle_to_camera - facing_angle + PI)

	var sector: int
	if num_angles == 8:
		sector = _get_sector_8(relative_angle)
	else:
		sector = _get_sector_4(relative_angle)

	if sector == _current_sector:
		return
	_current_sector = sector
	_apply_sector(sector)

# ============================================================================
# SECTOR CALCULATION (legacy)
# ============================================================================

## 4-direction sectors (each 90 degrees wide):
##   0 = front  (camera sees entity's front)
##   1 = right  (camera sees entity's right side)
##   2 = back   (camera sees entity's back)
##   3 = left   (camera sees entity's left side)
func _get_sector_4(angle: float) -> int:
	if angle >= -PI / 4.0 and angle < PI / 4.0:
		return 0  # front
	elif angle >= PI / 4.0 and angle < 3.0 * PI / 4.0:
		return 1  # right
	elif angle >= -3.0 * PI / 4.0 and angle < -PI / 4.0:
		return 3  # left
	else:
		return 2  # back

## 8-direction sectors (each 45 degrees wide).
func _get_sector_8(angle: float) -> int:
	var a := fmod(angle + TAU, TAU)
	var sector_size := TAU / 8.0
	var sector_index := int((a + sector_size * 0.5) / sector_size) % 8
	return sector_index

func _apply_sector(sector: int) -> void:
	if num_angles == 4:
		_apply_sector_4(sector)
	else:
		_apply_sector_8(sector)

func _apply_sector_4(sector: int) -> void:
	match sector:
		0:  # front
			_set_texture_safe(texture_front)
			flip_h = false
		1:  # right
			if texture_right:
				_set_texture_safe(texture_right)
				flip_h = false
			elif texture_left:
				_set_texture_safe(texture_left)
				flip_h = true
			else:
				_set_texture_safe(texture_front)
				flip_h = false
		2:  # back
			_set_texture_safe(texture_back)
			flip_h = false
		3:  # left
			if texture_left:
				_set_texture_safe(texture_left)
				flip_h = false
			elif texture_right:
				_set_texture_safe(texture_right)
				flip_h = true
			else:
				_set_texture_safe(texture_front)
				flip_h = false

func _apply_sector_8(sector: int) -> void:
	var tex: Texture2D = null
	var should_flip := false

	match sector:
		0:
			tex = texture_front
		1:
			tex = texture_front_right
			if not tex and texture_front_left:
				tex = texture_front_left
				should_flip = true
		2:
			tex = texture_right
			if not tex and texture_left:
				tex = texture_left
				should_flip = true
		3:
			tex = texture_back_right
			if not tex and texture_back_left:
				tex = texture_back_left
				should_flip = true
		4:
			tex = texture_back
		5:
			tex = texture_back_left
			if not tex and texture_back_right:
				tex = texture_back_right
				should_flip = true
		6:
			tex = texture_left
			if not tex and texture_right:
				tex = texture_right
				should_flip = true
		7:
			tex = texture_front_left
			if not tex and texture_front_right:
				tex = texture_front_right
				should_flip = true

	if not tex:
		var fallback_sector: int = [0, 1, 1, 2, 2, 3, 3, 0][sector]
		_apply_sector_4(fallback_sector)
		return

	_set_texture_safe(tex)
	flip_h = should_flip

func _set_texture_safe(tex: Texture2D) -> void:
	if tex and texture != tex:
		texture = tex

## Wrap angle to [-PI, PI] range.
static func _wrap_angle(a: float) -> float:
	a = fmod(a + PI, TAU)
	if a < 0:
		a += TAU
	return a - PI
