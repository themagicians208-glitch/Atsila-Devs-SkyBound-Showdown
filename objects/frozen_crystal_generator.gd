extends Node3D
class_name FrozenCrystalGenerator

signal activated

var is_activated := false
var _core: MeshInstance3D
var _material: StandardMaterial3D
var _time := 0.0

func _ready() -> void:
	_build()

func _build() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.48
	base_mesh.bottom_radius = 0.62
	base_mesh.height = 0.3
	base.mesh = base_mesh
	base.position.y = 0.15
	base.material_override = _make_material(Color("#183b68"), 0.2)
	add_child(base)
	_core = MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.0
	core_mesh.bottom_radius = 0.3
	core_mesh.height = 1.45
	_core.mesh = core_mesh
	_core.position.y = 0.95
	_material = _make_material(Color("#7deaff"), 0.85)
	_core.material_override = _material
	add_child(_core)

func _process(delta: float) -> void:
	_time += delta
	if _core == null:
		return
	_core.rotation.y += delta * (1.8 if is_activated else 0.55)
	_core.position.y = 0.95 + sin(_time * 2.0) * 0.06

func activate() -> bool:
	if is_activated:
		return false
	is_activated = true
	_material.albedo_color = Color("#fff3b0")
	_material.emission = Color("#a8f7ff")
	_material.emission_energy_multiplier = 2.4
	Audio.play("res://sounds/coin.ogg")
	activated.emit()
	return true

func _make_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.24
	material.emission_enabled = energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
