extends Node3D

## Shows three limb poses side by side, seen from the GAME camera at normal
## gameplay distance - i.e. exactly what the player would see.
## Centre = mid-stride, left = neutral, right = opposite stride.


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout

	# Lift the player clear of the level so nothing can hide it, and stop its
	# physics so it hovers while the camera catches up.
	var player: CharacterBody3D = main.get_node("Player")
	player.set_physics_process(false)
	player.global_position += Vector3(0, 4.0, 0)
	await get_tree().create_timer(1.7).timeout

	var centre: Node = player.get_node("Character")
	centre.set("animate_motion", false)
	centre.call("set_pose", -0.85, 0.30, 0.0, 0.62, 0.24)

	# Spread along the direction that is horizontal on screen for this camera.
	var side := Vector3(1, 0, -1).normalized()
	_add_pose(player.global_position - side * 1.7, 0.0, 0.0, 0.0, 0.0, 0.0)
	_add_pose(player.global_position + side * 1.7, 0.85, -0.30, 0.0, -0.62, -0.24)
	print("posed: left=neutral  centre=stride+  right=stride-")


func _add_pose(at: Vector3, leg: float, swing: float, crouch: float, flap: float, splay: float) -> void:
	var character: Node3D = load("res://objects/character.tscn").instantiate()
	add_child(character)
	character.set("player_index", 0)
	character.global_position = at
	character.set("animate_motion", false)
	character.call("set_pose", leg, swing, crouch, flap, splay)