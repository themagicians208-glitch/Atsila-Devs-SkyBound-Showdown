extends Area3D
class_name IceProjectile

@export var speed := 8.0
@export var damage := 8.0
var target: Node3D
var _life := 4.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	shape.shape = sphere
	add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	visual.mesh = mesh
	visual.material_override = _material()
	add_child(visual)
	body_entered.connect(_on_body_entered)

func launch(destination: Node3D) -> void:
	target = destination

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or not is_instance_valid(target):
		queue_free()
		return
	var offset := target.global_position - global_position
	if offset.length() < 0.35:
		if target.has_method("take_damage"):
			target.call("take_damage", damage, global_position, "crystal_phantom")
		queue_free()
		return
	global_position += offset.normalized() * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("take_damage"):
		body.call("take_damage", damage, global_position, "crystal_phantom")
	queue_free()

func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#9ff5ff")
	material.emission_enabled = true
	material.emission = Color("#4edfff")
	material.emission_energy_multiplier = 2.0
	return material
