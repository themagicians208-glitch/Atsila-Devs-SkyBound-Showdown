extends Area3D

var time := 0.0
var _base_y := 0.0

func _ready() -> void:
	_base_y = position.y
	add_to_group("collectible_coins")
	var persistent_id := str(get_meta("persistent_coin_id", ""))
	if not persistent_id.is_empty() and Progress.has_frozen_coin(persistent_id):
		call_deferred("queue_free")

# Collecting coins

func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("collect_coin"):
		return
	body.collect_coin()
	var persistent_id := str(get_meta("persistent_coin_id", ""))
	if not persistent_id.is_empty():
		Progress.collect_frozen_coin(persistent_id)
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/coin.ogg")
	queue_free()

# Rotating, animating up and down

func _process(delta: float) -> void:
	rotate_y(2.0 * delta)
	time += delta
	position.y = _base_y + sin(time * 2.5) * 0.18
