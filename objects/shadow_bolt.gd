extends Area3D
class_name ShadowBolt

## A bolt of mirror-dimension magic Malakar fires from his staff. It flies in a
## straight line, fades out after a short life, and fells any player it touches.

var direction := Vector3.FORWARD
var speed := 13.0
var life := 3.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	rotate_y(delta * 6.0)
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("die"):
		body.call("die")
		queue_free()