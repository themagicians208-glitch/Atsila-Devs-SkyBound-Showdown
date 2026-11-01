extends Area3D
class_name StickyZone

## Velcro / glue surface: kills all horizontal momentum the moment the player
## touches it, breaking their rhythm.

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_sticky"):
		body.set_sticky(true, self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("set_sticky"):
		body.set_sticky(false, self)