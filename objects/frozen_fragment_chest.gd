extends Area3D
class_name FrozenFragmentChest

signal fragment_recovered
var unlocked := false
var opened := false
var _lid: MeshInstance3D

func _ready() -> void:
	monitoring = true
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.8
	shape.shape = sphere
	add_child(shape)
	_build()
	body_entered.connect(_on_body_entered)

func _build() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.5, 0.7, 1.0)
	base.mesh = base_mesh
	base.position.y = 0.35
	base.material_override = _material(Color("#75dfff"), 0.6)
	add_child(base)
	_lid = MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.55, 0.18, 1.05)
	_lid.mesh = lid_mesh
	_lid.position = Vector3(0.0, 0.82, -0.08)
	_lid.material_override = _material(Color("#dffaff"), 0.9)
	add_child(_lid)

func unlock() -> void:
	unlocked = true
	_lid.material_override = _material(Color("#fff0a8"), 1.5)

func _on_body_entered(body: Node3D) -> void:
	if opened or not unlocked or not body.is_in_group("player"):
		return
	opened = true
	Audio.play("res://sounds/open.ogg" if ResourceLoader.exists("res://sounds/open.ogg") else "res://sounds/coin.ogg")
	Progress.recover_third_fragment()
	_lid.rotation.x = deg_to_rad(-65.0)
	fragment_recovered.emit()

func _material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

