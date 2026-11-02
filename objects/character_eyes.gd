extends Node3D

## Adds simple, friendly eyes to the character's head. Kept safe for a swapped
## model: it finds the head/torso by name and skips entirely if the model already
## provides its own eyes (or has no recognisable head node).

const CANDIDATE_PARENTS := [
	"character/root/torso", "root/torso", "torso", "Torso",
	"head", "Head", "root/head", "character/root/head",
]
const EYE_OFFSETS := [Vector3(-0.105, 0.39, 0.31), Vector3(0.105, 0.39, 0.31)]


func _ready() -> void:
	var head := _find_face_parent()
	if head == null or _already_has_eyes():
		return
	for offset in EYE_OFFSETS:
		_add_eye(head, offset)


func _find_face_parent() -> Node3D:
	for path in CANDIDATE_PARENTS:
		var node := get_node_or_null(path)
		if node is Node3D:
			return node
	return null


func _already_has_eyes() -> bool:
	for node in find_children("*", "Node3D", true, false):
		if String(node.name).to_lower().contains("eye"):
			return true
	return false


func _add_eye(parent: Node3D, offset: Vector3) -> void:
	var eye := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.052
	sphere.height = 0.104
	eye.mesh = sphere
	eye.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#10131b")
	material.roughness = 0.35
	eye.material_override = material
	parent.add_child(eye)
