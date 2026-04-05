extends Node3D
class_name FloatingText

## FloatingText - RPG-style loot popup that rises and fades out
## Usage: FloatingText.spawn(parent_node, world_position, "+1 Wood", Color.GREEN)

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
	_start_y = global_position.y
	_elapsed = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed / DURATION

	if t >= 1.0:
		queue_free()
		return

	# Rise
	global_position.y = _start_y + RISE_HEIGHT * t

	# Fade out
	if _label:
		var alpha: float = 1.0 - t
		_label.modulate.a = alpha


func _setup(text: String, color: Color) -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = 32
	_label.outline_size = 8
	_label.modulate = color
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	add_child(_label)


## Spawn floating text at a world position
## Returns the FloatingText node
static func spawn(parent: Node, pos: Vector3, text: String, color: Color = Color.WHITE) -> FloatingText:
	var ft := FloatingText.new()
	ft._setup(text, color)
	parent.add_child(ft)
	# Set position after adding to tree so global_position works
	ft.global_position = pos + Vector3(0, 1.0, 0)
	# Add small random horizontal offset so multiple texts don't overlap
	ft.global_position.x += randf_range(-0.3, 0.3)
	ft.global_position.z += randf_range(-0.3, 0.3)
	return ft


## Get the appropriate color for a resource name
static func color_for_resource(resource_name: String) -> Color:
	if RESOURCE_COLORS.has(resource_name):
		return RESOURCE_COLORS[resource_name]
	return Color.WHITE
