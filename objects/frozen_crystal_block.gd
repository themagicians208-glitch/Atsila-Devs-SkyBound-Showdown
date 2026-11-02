extends AnimatableBody3D
class_name FrozenCrystalBlock

signal moved(aligned: bool)

@export var target_slot := 0
@export var starting_slot := 0

var current_slot := 0
var _base_position := Vector3.ZERO
var _visual: MeshInstance3D

func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_base_position = position
	current_slot = target_slot if Progress.frozen_crystal_blocks_aligned else starting_slot
	_build()
	_apply_slot(false)

func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.78, 1.05, 0.78)
	shape.shape = box
	add_child(shape)
	_visual = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.72, 0.92, 0.72)
	_visual.mesh = mesh
	_visual.material_override = _material(Color("#74eaff"), 1.2)
	add_child(_visual)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.18
	core_mesh.height = 0.36
	core.mesh = core_mesh
	core.material_override = _material(Color("#fff3b0"), 1.8)
	core.position.y = 0.05
	add_child(core)

func try_interact(player: Node3D) -> bool:
	if Progress.frozen_crystal_blocks_aligned or player == null:
		return false
	if global_position.distance_to(player.global_position) > 2.4:
		return false
	current_slot = (current_slot + 1) % 3
	_apply_slot(true)
	Audio.play("res://sounds/coin.ogg")
	moved.emit(is_aligned())
	return true

func set_aligned() -> void:
	current_slot = target_slot
	_apply_slot(false)

func is_aligned() -> bool:
	return current_slot == target_slot

func _apply_slot(animated: bool) -> void:
	var destination := _base_position + Vector3((current_slot - 1) * 0.9, 0.0, 0.0)
	if animated:
		var tween := create_tween()
		tween.tween_property(self, "position", destination, 0.25)
	else:
		position = destination
	if _visual != null:
		_visual.rotation.y = float(current_slot) * PI * 0.5
		_visual.scale = Vector3.ONE * (1.12 if is_aligned() else 1.0)

func _material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
