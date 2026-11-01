extends Area3D
class_name FanTunnel

## A column of rising air that lifts the player while they are inside it.

@export var lift := 9.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_wind"):
		body.set_wind(lift, self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("set_wind"):
		body.set_wind(0.0, self)