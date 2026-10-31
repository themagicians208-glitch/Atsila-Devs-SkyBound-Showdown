extends Area3D

var time := 0.0

func _ready() -> void:
	add_to_group("collectible_coins")

# Collecting coins

func _on_body_entered(body) -> void:
	if body.has_method("collect_coin"):
		body.collect_coin()
		
		get_node("/root/Audio").play("res://sounds/coin.ogg") # Play sound
		queue_free() # Remove the coin entirely

# Rotating, animating up and down

func _process(delta) -> void:
	rotate_y(2 * delta) # Rotation
	position.y += (cos(time * 5) * 1) * delta # Sine movement
	
	time += delta
