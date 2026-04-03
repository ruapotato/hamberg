extends Sprite3D

## DirectionalSprite - Multi-angle 2D billboard sprite for 3D worlds
##
## Shows different sprite textures based on the camera's viewing angle relative
## to the entity's facing direction. Supports 4-direction (front/back/left/right)
## or 8-direction (with diagonals) modes.
##
## The sprite manually rotates on the Y axis to face the camera (like
## BILLBOARD_FIXED_Y) but does NOT use Godot's built-in billboard mode,
## since we need to control which texture is shown per angle sector.

# ============================================================================
# TEXTURES
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

## Number of directional texture variants: 4 or 8.
var num_angles: int = 4

# ============================================================================
# INTERNAL STATE
# ============================================================================

# Current angle sector index (0-3 for 4-dir, 0-7 for 8-dir). -1 = uninitialised.
var _current_sector: int = -1

# Cached previous values for change detection
var _prev_camera_pos: Vector3 = Vector3.INF
var _prev_facing_angle: float = INF

# Minimum angular change (radians) before re-evaluating the sector (~5 degrees)
const ANGLE_CHANGE_THRESHOLD: float = 0.087

# ============================================================================
# PUBLIC API
# ============================================================================

## Set textures for 4-direction mode (front, back, left, right).
func set_textures_4dir(front: Texture2D, back: Texture2D, left: Texture2D, right: Texture2D) -> void:
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
	# Disable Godot's built-in billboard — we handle orientation manually.
	billboard = BaseMaterial3D.BILLBOARD_DISABLED

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var camera_pos := camera.global_position

	# --- Y-axis billboard: rotate sprite to face camera on Y only ---
	var sprite_world_pos := global_position
	var dir_to_camera := camera_pos - sprite_world_pos
	dir_to_camera.y = 0.0
	if dir_to_camera.length_squared() > 0.001:
		# Make the sprite face the camera. Sprite3D forward is +Z when rotation is 0,
		# so we use look_at and let Godot figure out the quaternion, but only keep Y.
		var target_point := sprite_world_pos + dir_to_camera.normalized()
		# We cannot call look_at directly on the sprite because it may be a child of
		# a rotated container. Instead compute the desired global Y rotation.
		var desired_y := atan2(dir_to_camera.x, dir_to_camera.z)
		global_rotation.y = desired_y

	# --- Angle-sector texture selection ---
	# Skip expensive recalc if nothing changed enough
	var cam_moved := (_prev_camera_pos - camera_pos).length_squared() > 0.01
	var facing_changed := absf(_prev_facing_angle - facing_angle) > ANGLE_CHANGE_THRESHOLD
	if not cam_moved and not facing_changed and _current_sector != -1:
		return

	_prev_camera_pos = camera_pos
	_prev_facing_angle = facing_angle

	# Compute relative angle: camera direction relative to entity facing.
	# angle_to_camera is the world angle from the entity to the camera.
	var to_camera := camera_pos - sprite_world_pos
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.001:
		return

	var angle_to_camera := atan2(to_camera.x, to_camera.z)
	# relative_angle: 0 = camera seeing entity's front, PI/-PI = seeing entity's back.
	# When the camera is opposite the entity's facing direction, we see the front,
	# so we add PI to flip the relationship.
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
# SECTOR CALCULATION
# ============================================================================

## 4-direction sectors (each 90 degrees wide):
##   0 = front  (camera sees entity's front)
##   1 = right  (camera sees entity's right side)
##   2 = back   (camera sees entity's back)
##   3 = left   (camera sees entity's left side)
func _get_sector_4(angle: float) -> int:
	# angle in [-PI, PI], 0 = front
	if angle >= -PI / 4.0 and angle < PI / 4.0:
		return 0  # front
	elif angle >= PI / 4.0 and angle < 3.0 * PI / 4.0:
		return 1  # right
	elif angle >= -3.0 * PI / 4.0 and angle < -PI / 4.0:
		return 3  # left
	else:
		return 2  # back

## 8-direction sectors (each 45 degrees wide).
## Sectors: 0=front, 1=front-right, 2=right, 3=back-right,
##          4=back, 5=back-left, 6=left, 7=front-left
func _get_sector_8(angle: float) -> int:
	# Each sector is PI/4 (45 degrees) wide, centered on its cardinal/diagonal.
	# Normalize angle to [0, TAU) for simpler boundary math.
	var a := fmod(angle + TAU, TAU)  # [0, TAU)
	var sector_size := TAU / 8.0  # PI/4
	# Sector 0 (front) is centered at angle=0, spanning [-sector_size/2, sector_size/2].
	# After shifting by half a sector, integer division gives sector index.
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
				# Mirror the left texture
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
				# Mirror the right texture
				_set_texture_safe(texture_right)
				flip_h = true
			else:
				_set_texture_safe(texture_front)
				flip_h = false

func _apply_sector_8(sector: int) -> void:
	# Sectors: 0=front, 1=front-right, 2=right, 3=back-right,
	#          4=back, 5=back-left, 6=left, 7=front-left
	var tex: Texture2D = null
	var should_flip := false

	match sector:
		0:  # front
			tex = texture_front
		1:  # front-right
			tex = texture_front_right
			if not tex and texture_front_left:
				tex = texture_front_left
				should_flip = true
		2:  # right
			tex = texture_right
			if not tex and texture_left:
				tex = texture_left
				should_flip = true
		3:  # back-right
			tex = texture_back_right
			if not tex and texture_back_left:
				tex = texture_back_left
				should_flip = true
		4:  # back
			tex = texture_back
		5:  # back-left
			tex = texture_back_left
			if not tex and texture_back_right:
				tex = texture_back_right
				should_flip = true
		6:  # left
			tex = texture_left
			if not tex and texture_right:
				tex = texture_right
				should_flip = true
		7:  # front-left
			tex = texture_front_left
			if not tex and texture_front_right:
				tex = texture_front_right
				should_flip = true

	# Fallback to 4-dir if diagonal texture missing
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
