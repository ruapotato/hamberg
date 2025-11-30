extends RefCounted
class_name ChunkData

## ChunkData - Stores persistent information about spawned objects in a chunk
## This allows chunks to remember their state between load/unload cycles

class ObjectData:
	var object_type: String  # "tree", "rock", "grass", etc.
	var object_id: int = -1  # Index within the object type array
	var position: Vector3
	var rotation: Vector3
	var scale: Vector3
	var is_destroyed: bool = false  # Track if player removed this object

	func to_dict() -> Dictionary:
		return {
			"type": object_type,
			"id": object_id,
			"pos": [position.x, position.y, position.z],
			"rot": [rotation.x, rotation.y, rotation.z],
			"scale": [scale.x, scale.y, scale.z],
			"destroyed": is_destroyed
		}

	static func from_dict(data: Dictionary) -> ObjectData:
		var obj_data := ObjectData.new()
		obj_data.object_type = data.get("type", "")
		obj_data.object_id = data.get("id", -1)
		var pos = data.get("pos", [0, 0, 0])
		obj_data.position = Vector3(pos[0], pos[1], pos[2])
		var rot = data.get("rot", [0, 0, 0])
		obj_data.rotation = Vector3(rot[0], rot[1], rot[2])
		var scl = data.get("scale", [1, 1, 1])
		obj_data.scale = Vector3(scl[0], scl[1], scl[2])
		obj_data.is_destroyed = data.get("destroyed", false)
		return obj_data

var chunk_position: Vector2i
var objects: Array[ObjectData] = []
var is_generated: bool = false  # Has this chunk been procedurally generated yet?

func _init(pos: Vector2i = Vector2i.ZERO) -> void:
	chunk_position = pos

## Add an object to this chunk's data
func add_object(obj_type: String, pos: Vector3, rot: Vector3, scl: Vector3, obj_id: int = -1) -> ObjectData:
	var obj_data := ObjectData.new()
	obj_data.object_type = obj_type
	obj_data.object_id = obj_id
	obj_data.position = pos
	obj_data.rotation = rot
	obj_data.scale = scl
	objects.append(obj_data)
	return obj_data

## Mark an object as destroyed (for when player removes it)
func destroy_object_at_position(pos: Vector3, threshold: float = 0.5) -> bool:
	for obj_data in objects:
		if obj_data.position.distance_to(pos) < threshold:
			obj_data.is_destroyed = true
			return true
	return false

## Mark an object as destroyed by index
func mark_object_destroyed(index: int) -> void:
	if index >= 0 and index < objects.size():
		objects[index].is_destroyed = true

## Get all active (not destroyed) objects
func get_active_objects() -> Array[ObjectData]:
	var active: Array[ObjectData] = []
	for obj_data in objects:
		if not obj_data.is_destroyed:
			active.append(obj_data)
	return active

## Get all destroyed objects
func get_destroyed_objects() -> Array[ObjectData]:
	var destroyed: Array[ObjectData] = []
	for obj_data in objects:
		if obj_data.is_destroyed:
			destroyed.append(obj_data)
	return destroyed

## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	var objects_data: Array = []
	for obj in objects:
		objects_data.append(obj.to_dict())

	return {
		"chunk_pos": [chunk_position.x, chunk_position.y],
		"generated": is_generated,
		"objects": objects_data
	}

## Deserialize from dictionary
static func from_dict(data: Dictionary):
	var chunk_pos_arr = data.get("chunk_pos", [0, 0])
	var chunk_data = new(Vector2i(chunk_pos_arr[0], chunk_pos_arr[1]))
	chunk_data.is_generated = data.get("generated", false)

	var objects_data = data.get("objects", [])
	for obj_dict in objects_data:
		var obj_data := ObjectData.from_dict(obj_dict)
		chunk_data.objects.append(obj_data)

	return chunk_data
