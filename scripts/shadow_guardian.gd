extends Area3D
class_name ShadowGuardian

@export var patrol_radius: float = 0.72
@export var patrol_speed: float = 1.7
@export var hover_height: float = 1.15

var _phase: float = 0.0
var _origin: Vector3 = Vector3.ZERO


func _ready() -> void:
	_origin = position
	_phase = float(get_instance_id() % 1000) * 0.01
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_phase += delta * patrol_speed
	position = _origin + Vector3(cos(_phase) * patrol_radius, sin(_phase * 2.0) * 0.16 + hover_height, sin(_phase) * patrol_radius)
	rotate_y(delta * 0.8)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("die"):
		body.call("die")
