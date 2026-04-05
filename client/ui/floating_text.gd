extends Node3D

## FloatingText - RPG-style loot popup that rises and fades out

const RISE_HEIGHT: float = 2.0
const DURATION: float = 2.0

# Color mapping for resource types
const RESOURCE_COLORS: Dictionary = {
	"wood": Color(0.3, 0.9, 0.3),
	"plant_fiber": Color(0.3, 0.9, 0.3),
	"stone": Color(0.8, 0.8, 0.9),
	"iron": Color(0.8, 0.8, 0.9),
	"copper": Color(0.8, 0.8, 0.9),
	"charcoal": Color(0.5, 0.5, 0.5),
}

var _label: Label3D = null
var _start_y: float = 0.0
var _elapsed: float = 0.0


func _ready() -> void:
	_elapsed = 0.0
	# _start_y is set after global_position is assigned (see first _process frame)


func _process(delta: float) -> void:
	# Capture start position on first frame (global_position is set after add_child)
	if _elapsed == 0.0:
		_start_y = global_position.y

	_elapsed += delta
	var t: float = _elapsed / DURATION

	if t >= 1.0:
		queue_free()
		return

	# Rise
	global_position.y = _start_y + RISE_HEIGHT * t

	# Fade out
	if _label:
		_label.modulate.a = 1.0 - t


func setup(text: String, color: Color) -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = 32
	_label.outline_size = 8
	_label.modulate = color
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	add_child(_label)
