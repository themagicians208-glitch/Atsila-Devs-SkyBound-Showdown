extends Area3D
class_name SlipperyZone

## Ice / oil slick: strips the player of traction so they slide and cannot stop.

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_slippery"):
		body.set_slippery(true, self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("set_slippery"):
		body.set_slippery(false, self)