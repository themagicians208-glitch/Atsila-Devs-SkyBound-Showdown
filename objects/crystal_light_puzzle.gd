extends Node3D
class_name CrystalLightPuzzle

signal solved

var _crystals: Array[MeshInstance3D] = []
var _rotations: Array[int] = [0, 0, 0]
var _targets: Array[int] = [1, 2, 3]
var is_solved := false
var _time := 0.0

func _ready() -> void:
	_build()
	if Progress.crystal_light_solved:
		is_solved = true
		_rotations = _targets.duplicate()

func _build() -> void:
	for index in 3:
		var crystal := MeshInstance3D.new()
		crystal.name = "LightCrystal_%d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.32
		mesh.height = 1.5
		crystal.mesh = mesh
		crystal.position = Vector3(float(index - 1) * 1.35, 0.8, 0.0)
		crystal.material_override = _material(Color("#6ce7ff" if index == 0 else "#a58cff" if index == 1 else "#d8ffff"))
		add_child(crystal)
		_crystals.append(crystal)

func _process(delta: float) -> void:
	_time += delta
	for index in _crystals.size():
		var crystal := _crystals[index]
		crystal.position.y = 0.8 + sin(_time * 2.0 + float(index)) * 0.08
		crystal.rotation.y += delta * (0.35 if is_solved else 0.12)

func try_interact(player: Node3D) -> bool:
	if is_solved or global_position.distance_to(player.global_position) > 3.2:
		return false
	var nearest := 0
	var distance := INF
	for index in _crystals.size():
		var current := _crystals[index].global_position.distance_to(player.global_position)
		if current < distance:
			distance = current
			nearest = index
	_rotations[nearest] = (_rotations[nearest] + 1) % 4
	_crystals[nearest].rotation.y = float(_rotations[nearest]) * PI * 0.5
	Audio.play("res://sounds/coin.ogg")
	if _rotations == _targets:
		is_solved = true
		Progress.mark_crystal_light_solved()
		solved.emit()
	return true

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.3
	return material
