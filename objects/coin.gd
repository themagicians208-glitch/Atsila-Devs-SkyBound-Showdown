extends Area3D

var time := 0.0
var _base_y := 0.0

func _ready() -> void:
	_base_y = position.y
	add_to_group("collectible_coins")

# Collecting coins

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("collect_coin"):
		return
	body.collect_coin()
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/coin.ogg")
	queue_free()

# Rotating, animating up and down

func _process(delta: float) -> void:
	rotate_y(2.0 * delta)
	time += delta
	position.y = _base_y + sin(time * 2.5) * 0.18
