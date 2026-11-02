extends Node

## Local split screen: both players get their own attack binding, and the
## inventory lists both.

func _ready() -> void:
	get_tree().set_meta("level_number", 1)
	get_tree().set_meta("local_coop", true)
	get_tree().set_meta("local_p1_device", "keyboard")
	get_tree().set_meta("local_p2_device", "keyboard")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.2).timeout

	var p1: CharacterBody3D = main.get_node("Player")
	var p2: CharacterBody3D = main.get("player_two")
	print("player two exists: %s" % (p2 != null))
	for pair in [[p1, "player 1"], [p2, "player 2"]]:
		var who: CharacterBody3D = pair[0]
		if who == null:
			continue
		print("%s: attack action '%s'" % [pair[1], who.get("action_attack")])
	print("enemies in the level: %d" % get_tree().get_nodes_in_group("enemies").size())
	var hud: Control = main.get_node("HUD")
	print("inventory lists %d player(s)" % (hud.get("_players") as Array).size())

	print("player 2 cooldown before: %.2f" % float(p2.get("attack_cooldown_left")))
	Input.action_press("p2_attack")
	for i in 3:
		await get_tree().physics_frame
	Input.action_release("p2_attack")
	await get_tree().physics_frame
	print("player 2 cooldown after pressing p2_attack: %.2f  (bigger = the swing fired)" % float(p2.get("attack_cooldown_left")))
	print("player 1 cooldown (should be 0): %.2f" % float(p1.get("attack_cooldown_left")))
	get_tree().quit()
