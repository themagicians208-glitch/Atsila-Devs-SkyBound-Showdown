extends Area3D
class_name ShadowGuardian

const SHADOW_BOLT_SCRIPT := preload("res://objects/shadow_bolt.gd")

@export var patrol_radius: float = 0.72
@export var patrol_speed: float = 1.7
@export var hover_height: float = 1.15

var _phase: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var guardian_type := "Shadow Knight"
var _bolt_timer := 1.4


func _ready() -> void:
	_origin = position
	_phase = float(get_instance_id() % 1000) * 0.01
	guardian_type = str(get_meta("guardian_type", "Shadow Knight"))
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_phase += delta * patrol_speed
	position = _origin + Vector3(cos(_phase) * patrol_radius, sin(_phase * 2.0) * 0.16 + hover_height, sin(_phase) * patrol_radius)
	rotate_y(delta * 0.8)
	if guardian_type == "Void Mage":
		_bolt_timer -= delta
		if _bolt_timer <= 0.0:
			_bolt_timer = 3.2
			var target := get_tree().get_first_node_in_group("player") as Node3D
			if target != null and global_position.distance_to(target.global_position) < 16.0:
				_fire_bolt(target)


func _fire_bolt(target: Node3D) -> void:
	var host := get_parent()
	if host == null:
		return
	var bolt := Area3D.new()
	bolt.name = "VoidBolt"
	bolt.set_script(SHADOW_BOLT_SCRIPT)
	bolt.collision_layer = 0
	bolt.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.24
	shape.shape = sphere
	bolt.add_child(shape)
	var visual := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.18
	orb.height = 0.36
	visual.mesh = orb
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#79e9ff")
	material.emission_enabled = true
	material.emission = Color("#79e9ff")
	visual.material_override = material
	bolt.add_child(visual)
	host.add_child(bolt)
	bolt.global_position = global_position + Vector3(0, 1.0, 0)
	var aim := target.global_position + Vector3(0, 0.75, 0) - bolt.global_position
	bolt.set("direction", aim.normalized())
	bolt.set("speed", 9.5)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("die"):
		body.call("die")
