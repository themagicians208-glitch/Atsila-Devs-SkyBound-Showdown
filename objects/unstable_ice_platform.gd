extends StaticBody3D
class_name UnstableIcePlatform

@export var reset_delay := 1.15
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _cooling := false

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.1, 0.14, 2.1)
	_mesh.mesh = box
	_mesh.material_override = _material()
	add_child(_mesh)
	_shape = CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = box.size
	_shape.shape = collision
	add_child(_shape)
	var trigger := Area3D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	var trigger_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(2.25, 1.2, 2.25)
	trigger_shape.shape = trigger_box
	trigger.add_child(trigger_shape)
	add_child(trigger)
	trigger.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if _cooling or not body.is_in_group("player"):
		return
	_cooling = true
	Audio.play("res://sounds/land.ogg")
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3.ONE * 0.82, 0.22)
	tween.tween_callback(func(): _shape.disabled = true)
	tween.tween_interval(reset_delay)
	tween.tween_callback(func():
		_shape.disabled = false
		_mesh.scale = Vector3.ONE
		_cooling = false
	)

func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#a9efff")
	material.emission_enabled = true
	material.emission = Color("#5fdcff")
	material.emission_energy_multiplier = 0.8
	material.roughness = 0.2
	return material
