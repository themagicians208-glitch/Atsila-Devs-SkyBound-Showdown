extends Area3D
class_name SecondFragmentChest

signal fragment_recovered
var unlocked := false
var opened := false
var _lid: MeshInstance3D
var _fragment: MeshInstance3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.8
	shape.shape = sphere
	add_child(shape)
	_build()
	if Progress.second_fragment_recovered:
		unlocked = true
		opened = true
		_lid.rotation.x = deg_to_rad(-65.0)
		_fragment.visible = true
		_fragment.position.y = 1.6
	body_entered.connect(_on_body_entered)

func _build() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.5, 0.7, 1.0)
	base.mesh = base_mesh
	base.position.y = 0.35
	base.material_override = _material(Color("#47256a"), 0.55)
	add_child(base)
	_lid = MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.55, 0.18, 1.05)
	_lid.mesh = lid_mesh
	_lid.position = Vector3(0.0, 0.82, -0.08)
	_lid.material_override = _material(Color("#a26cff"), 0.9)
	add_child(_lid)
	_fragment = MeshInstance3D.new()
	var fragment_mesh := SphereMesh.new()
	fragment_mesh.radius = 0.24
	fragment_mesh.height = 0.48
	_fragment.mesh = fragment_mesh
	_fragment.position = Vector3(0.0, 0.95, 0.0)
	_fragment.material_override = _material(Color("#ffe49a"), 2.0)
	_fragment.visible = false
	add_child(_fragment)

func unlock() -> void:
	unlocked = true

func _on_body_entered(body: Node3D) -> void:
	if opened or not unlocked or not body.is_in_group("player"):
		return
	opened = true
	Progress.recover_second_fragment()
	_fragment.visible = true
	var tween := create_tween()
	tween.tween_property(_lid, "rotation:x", deg_to_rad(-65.0), 0.45)
	tween.parallel().tween_property(_fragment, "position:y", 1.6, 0.8)
	tween.tween_callback(fragment_recovered.emit)

func _material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
