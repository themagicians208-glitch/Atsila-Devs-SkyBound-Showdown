extends Node

## Puts the player beside the sky sentry, mid-slash, so the swing pose and the
## slash flash can be seen in one shot. The player's physics is off so they hover
## next to the enemy instead of falling out of the sky.

func _ready() -> void:
	get_tree().set_meta("level_number", 1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout

	var player: CharacterBody3D = main.get_node("Player")
	var enemy: Node3D = get_tree().get_nodes_in_group("enemies")[0]
	player.set_physics_process(false)
	player.global_position = enemy.global_position + Vector3(0.0, -0.7, -1.6)
	player.rotation.y = 0.0
	var view: Node3D = main.get_node("View")
	view.rotation.y = PI
	await get_tree().create_timer(0.7).timeout
	player.call("_swing")
	# Hold the pose at its peak so the screenshot catches the swing.
	var character: Node3D = player.get_node("Character")
	character.call("set_swing", 1.0, 0)
