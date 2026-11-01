extends Node3D
class_name ShadowWolf

signal defeated

@export var max_health := 6
@export var movement_speed := 5.0
@export var contact_damage := 8.0
var health := 6
var _dead := false
var _time := 0.0
var _home := Vector3.ZERO
var _visual: Node3D
var _body_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_home = global_position
	_build()

func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#56307d")
	_body_material.emission_enabled = true
	_body_material.emission = Color("#a05cff") * 0.35
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.6
	body.mesh = mesh
	body.material_override = _body_material
	body.rotation.x = PI * 0.5
	_visual.add_child(body)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.1
		eye_mesh.height = 0.2
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.18, 0.18, 0.48)
		eye.material_override = _glow(Color("#f0d3ff"))
		_visual.add_child(eye)
	for side in [-1.0, 1.0]:
		for front in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var leg_mesh := CapsuleMesh.new()
			leg_mesh.radius = 0.13
			leg_mesh.height = 0.65
			leg.mesh = leg_mesh
			leg.position = Vector3(side * 0.32, -0.62, front * 0.32)
			leg.material_override = _body_material
			_visual.add_child(leg)

func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	return material

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	_visual.position.y = sin(_time * 4.0) * 0.08
	var target := get_tree().get_first_node_in_group("player") as Node3D
	if target == null or bool(target.get("is_dead")):
		return
	var offset := target.global_position - global_position
	if offset.length() <= 11.0:
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length() > 0.8:
			global_position += flat.normalized() * movement_speed * delta
			rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 5.0)
	if global_position.distance_to(target.global_position) < 1.5 and target.has_method("take_damage"):
		target.call("take_damage", contact_damage, global_position, "shadow_wolf")

func take_hit(amount: int, _from: Vector3) -> bool:
	if _dead:
		return false
	health -= amount
	_body_material.albedo_color = Color.WHITE
	var tween := create_tween()
	tween.tween_property(_body_material, "albedo_color", Color("#56307d"), 0.12)
	if health <= 0:
		_dead = true
		defeated.emit()
		queue_free()
	return true
