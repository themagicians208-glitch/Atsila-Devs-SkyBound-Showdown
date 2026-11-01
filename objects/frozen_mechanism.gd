extends Node3D
class_name FrozenMechanism

signal activated

@export var mechanism_name := "Frozen Switch"
var is_activated := false
var _core: MeshInstance3D
var _material: StandardMaterial3D
var _time := 0.0

func _ready() -> void:
	_build()

func _build() -> void:
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.5
	base_mesh.bottom_radius = 0.62
	base_mesh.height = 0.35
	base.mesh = base_mesh
	base.position.y = 0.18
	base.material_override = _material_for(Color("#173b68"), 0.2)
	add_child(base)
	_core = MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.0
	core_mesh.bottom_radius = 0.28
	core_mesh.height = 1.2
	_core.mesh = core_mesh
	_core.position.y = 0.9
	_material = _material_for(Color("#68dfff"), 0.75)
	_core.material_override = _material
	add_child(_core)

func _process(delta: float) -> void:
	_time += delta
	if _core != null:
		_core.rotation.y += delta * (1.8 if is_activated else 0.6)
		_core.position.y = 0.9 + sin(_time * 2.0) * 0.06

func activate() -> bool:
	if is_activated:
		return false
	is_activated = true
	Audio.play("res://sounds/coin.ogg")
	_material.albedo_color = Color("#f2ffff")
	_material.emission = Color("#b7f7ff")
	_material.emission_energy_multiplier = 2.2
	activated.emit()
	return true

func _material_for(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.25
	material.emission_enabled = energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
