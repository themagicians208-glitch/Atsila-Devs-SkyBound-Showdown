extends Node

## Do checkpoint triggers fire when a player walks into them? The player is not
## teleported here - the checkpoint is moved in front of them and they walk into
## it, the way a player would, because a teleported body is not a fair test.

func _ready() -> void:
	get_tree().set_meta("level_number", 1)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout

	var player: CharacterBody3D = main.get("player")
	var problems: Array = []
	var checkpoints := get_tree().get_nodes_in_group("course_checkpoints")
	checkpoints.sort_custom(func(a, b): return int(a.get_meta("checkpoint_index")) < int(b.get_meta("checkpoint_index")))
	print("checkpoints: %d, active index before: %d" % [checkpoints.size(), main.get("active_checkpoint")])
	if checkpoints.size() < 2:
		print("no second checkpoint to test")
		get_tree().quit(1)
		return

	# Put the second checkpoint two units north of the player, then walk into it.
	var second := checkpoints[1] as Node3D
	var start := player.global_position
	second.global_position = Vector3(start.x, start.y - 0.55, start.z + 2.4)
	await get_tree().physics_frame
	Input.action_press("move_forward")
	for frame in 90:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await get_tree().physics_frame
	print("player walked to %s; active index now %d, respawn point %s" % [
		player.global_position.round(), main.get("active_checkpoint"),
		(main.get("checkpoint_position") as Vector3).round()])
	if int(main.get("active_checkpoint")) != int(second.get_meta("checkpoint_index")):
		problems.append("walking into checkpoint %d did not claim it" % int(second.get_meta("checkpoint_index")))
	# The respawn point is the checkpoint's designed spot (where the level put it),
	# not wherever the node happens to be now - so compare it against the spawn.
	if (main.get("checkpoint_position") as Vector3).distance_to(start) < 5.0:
		problems.append("the respawn point did not move to the checkpoint (still %s)" % (main.get("checkpoint_position") as Vector3).round())

	if problems.is_empty():
		print("\nCHECKPOINT OK - walking into a checkpoint claims it and moves the respawn")
	else:
		print("\nCHECKPOINT PROBLEMS (%d):" % problems.size())
		for problem in problems:
			print("  - %s" % problem)
	get_tree().quit(0 if problems.is_empty() else 1)
